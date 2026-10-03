-- WSID STATUS PATCH ONLY
-- Membaca status order FAYUPEDIA tanpa mengubah submit_order / deposit / Telegram / fitur lain.
-- Urutan request:
--   1) <base_url>/status  : api_id + api_key + order
--   2) fallback <base_url>/order : api_id + api_key + action=status + order
-- ID yang dipakai SELALU provider_order_id (contoh 5519511), bukan UUID order WSID.

create or replace function public.wsid_provider_order_status(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_order record;
  v_provider record;
  v_provider_order text;
  v_body text;
  v_http_status integer := 0;
  v_content text := '';
  v_json jsonb := '{}'::jsonb;
  v_remote text := '';
  v_local text := '';
  v_changed boolean := false;
  v_allowed boolean := false;
  v_base text;
  v_endpoint text := '';
  v_msg text := '';
  v_attempt integer := 0;
  v_status_found boolean := false;
begin
  select o.* into v_order
  from public.orders o
  where o.id::text = p_order_id
  limit 1;

  if not found then
    return jsonb_build_object('status',false,'msg','Order tidak ditemukan.');
  end if;

  select exists(
    select 1 from public.profiles p
    where p.id=auth.uid() and p.role='admin'
  ) or v_order.user_id=auth.uid()
  into v_allowed;

  if not v_allowed then
    return jsonb_build_object('status',false,'msg','Akses ditolak.');
  end if;

  select * into v_provider
  from public.providers
  where name='FAYUPEDIA'
  order by updated_at desc nulls last
  limit 1;

  if not found or coalesce(v_provider.is_active,true)=false then
    return jsonb_build_object('status',false,'msg','Koneksi provider FAYUPEDIA tidak aktif.');
  end if;

  v_provider_order := trim(coalesce(to_jsonb(v_order)->>'provider_order_id',''));
  if v_provider_order='' then
    return jsonb_build_object('status',false,'msg','Provider order ID belum tersedia.');
  end if;

  if coalesce(trim(v_provider.base_url),'')='' or coalesce(trim(v_provider.api_key),'')='' then
    return jsonb_build_object('status',false,'msg','Base URL/API key provider belum lengkap.');
  end if;

  v_base := regexp_replace(trim(v_provider.base_url), '/+$', '');

  -- ============================================================
  -- ATTEMPT 1: endpoint status yang terpisah.
  -- ============================================================
  v_attempt := 1;
  v_endpoint := v_base||'/status';
  v_body := 'api_id='||extensions.urlencode(trim(coalesce(v_provider.api_id::varchar,'')))
         ||'&api_key='||extensions.urlencode(trim(v_provider.api_key))
         ||'&order='||extensions.urlencode(v_provider_order);

  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','20');
    select r.status, r.content into v_http_status, v_content
    from extensions.http_post(v_endpoint,v_body,'application/x-www-form-urlencoded') r;
  exception when others then
    v_http_status := 0;
    v_content := '';
    v_msg := sqlerrm;
  end;

  if v_http_status between 200 and 299 then
    begin
      v_json := coalesce(v_content,'{}')::jsonb;
    exception when others then
      v_json := '{}'::jsonb;
    end;

    -- Jangan membaca wrapper status=true/success sebagai status order.
    v_remote := lower(trim(coalesce(
      v_json->'data'->>'status',
      v_json->'data'->'order'->>'status',
      v_json->'order'->>'status',
      v_json->>'order_status',
      v_json->'data'->>'order_status',
      case when lower(trim(coalesce(v_json->>'status',''))) in
        ('pending','processing','success','completed','complete','partial','cancelled','canceled','failed','error','rejected')
        then v_json->>'status' else null end,
      ''
    )));

    if v_remote<>'' then v_status_found := true; end if;
  end if;

  -- ============================================================
  -- ATTEMPT 2: fallback ke endpoint /order yang dipakai submit_order.
  -- ============================================================
  if not v_status_found then
    v_attempt := 2;
    v_endpoint := v_base||'/order';
    v_body := 'api_id='||extensions.urlencode(trim(coalesce(v_provider.api_id::varchar,'')))
           ||'&api_key='||extensions.urlencode(trim(v_provider.api_key))
           ||'&action=status'
           ||'&order='||extensions.urlencode(v_provider_order);

    begin
      perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','20');
      select r.status, r.content into v_http_status, v_content
      from extensions.http_post(v_endpoint,v_body,'application/x-www-form-urlencoded') r;
    exception when others then
      v_http_status := 0;
      v_content := '';
      v_msg := sqlerrm;
    end;

    begin
      v_json := coalesce(v_content,'{}')::jsonb;
    exception when others then
      v_json := '{}'::jsonb;
    end;

    v_remote := lower(trim(coalesce(
      v_json->'data'->>'status',
      v_json->'data'->'order'->>'status',
      v_json->'order'->>'status',
      v_json->>'order_status',
      v_json->'data'->>'order_status',
      case when lower(trim(coalesce(v_json->>'status',''))) in
        ('pending','processing','success','completed','complete','partial','cancelled','canceled','failed','error','rejected')
        then v_json->>'status' else null end,
      ''
    )));
    if v_remote<>'' then v_status_found := true; end if;
  end if;

  if not v_status_found then
    return jsonb_build_object(
      'status',false,
      'updated',false,
      'msg',coalesce(nullif(v_json->>'msg',''),nullif(v_json->>'message',''),nullif(v_msg,''),'Provider tidak mengembalikan status order.'),
      'provider_order_id',v_provider_order,
      'http_status',v_http_status,
      'endpoint',v_endpoint,
      'attempt',v_attempt
    );
  end if;

  if v_remote in ('completed','complete','success','successful','done','finished') then
    v_local := 'success';
  elsif v_remote in ('processing','in progress','in_progress','running','working') then
    v_local := 'processing';
  elsif v_remote in ('pending','waiting','queued','queue') then
    v_local := 'pending';
  elsif v_remote in ('partial','partially completed','partially_complete') then
    v_local := 'partial';
  elsif v_remote in ('cancel','canceled','cancelled','failed','failure','error','rejected','reject','refunded','refund') then
    v_local := 'failed';
  else
    return jsonb_build_object(
      'status',true,'updated',false,
      'order_id',v_order.id::text,
      'provider_order_id',v_provider_order,
      'provider_status',v_remote,
      'local_status',v_order.status,
      'http_status',v_http_status,
      'endpoint',v_endpoint,
      'attempt',v_attempt
    );
  end if;

  if to_jsonb(v_order) ? 'provider_status' then
    if lower(coalesce(v_order.status::text,'')) is distinct from v_local
       or lower(coalesce(to_jsonb(v_order)->>'provider_status','')) is distinct from v_remote then
      update public.orders
      set status=v_local,
          provider_status=v_remote,
          updated_at=now()
      where id::text=p_order_id;
      v_changed := true;
    end if;
  else
    if lower(coalesce(v_order.status::text,'')) is distinct from v_local then
      update public.orders
      set status=v_local,
          updated_at=now()
      where id::text=p_order_id;
      v_changed := true;
    end if;
  end if;

  return jsonb_build_object(
    'status',true,
    'updated',v_changed,
    'order_id',v_order.id::text,
    'provider_order_id',v_provider_order,
    'provider_status',v_remote,
    'local_status',v_local,
    'http_status',v_http_status,
    'endpoint',v_endpoint,
    'attempt',v_attempt
  );
exception when others then
  return jsonb_build_object('status',false,'msg','Sinkronisasi gagal: '||sqlerrm,'provider_order_id',v_provider_order);
end;
$fn$;

grant execute on function public.wsid_provider_order_status(text) to authenticated;

create or replace function public.sync_my_order_statuses()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  r record;
  x jsonb;
  v_checked integer := 0;
  v_updated integer := 0;
  v_failed integer := 0;
begin
  if auth.uid() is null then
    return jsonb_build_object('status',false,'msg','Belum login.');
  end if;

  for r in
    select o.id
    from public.orders o
    where o.user_id=auth.uid()
      and lower(coalesce(o.status::text,'')) in ('pending','processing','in progress','in_progress')
    order by o.created_at desc
    limit 20
  loop
    v_checked := v_checked + 1;
    x := public.wsid_provider_order_status(r.id::text);
    if coalesce((x->>'status')::boolean,false) then
      if coalesce((x->>'updated')::boolean,false) then
        v_updated := v_updated + 1;
      end if;
    else
      v_failed := v_failed + 1;
    end if;
  end loop;

  return jsonb_build_object('status',true,'checked',v_checked,'updated',v_updated,'failed',v_failed);
end;
$fn$;

grant execute on function public.sync_my_order_statuses() to authenticated;
