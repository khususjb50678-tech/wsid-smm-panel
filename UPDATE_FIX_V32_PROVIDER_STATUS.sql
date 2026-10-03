-- WSID SMM PANEL V32 - PROVIDER STATUS SYNC
-- ONLY changes order-status synchronization. Existing order creation, Telegram,
-- deposit, target privacy, news, terms, status-info and Safe Browser features stay intact.
-- Provider order ID defaults to public.orders.id because the provider and panel
-- screenshots show the same order ID. If a provider_order_id column exists, it is used.

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
  v_http_status integer;
  v_content text;
  v_json jsonb;
  v_remote text;
  v_local text;
  v_changed boolean := false;
  v_allowed boolean := false;
begin
  select o.* into v_order
  from public.orders o
  where o.id::text = p_order_id
  limit 1;

  if not found then
    return jsonb_build_object('status',false,'msg','Order tidak ditemukan.');
  end if;

  -- Only the owner or an admin may force a provider status check.
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

  -- Prefer provider_order_id when present; otherwise use the panel order ID.
  v_provider_order := coalesce(to_jsonb(v_order)->>'provider_order_id', v_order.id::text);
  if coalesce(trim(v_provider_order),'')='' then
    v_provider_order := v_order.id::text;
  end if;

  if coalesce(trim(v_provider.base_url),'')='' or coalesce(trim(v_provider.api_key),'')='' then
    return jsonb_build_object('status',false,'msg','Base URL/API key provider belum lengkap.');
  end if;

  -- FAYUPEDIA-style SMM API: key + action=status + order=<provider order id>.
  v_body := 'key='||extensions.urlencode(trim(v_provider.api_key))
         ||'&action=status'
         ||'&order='||extensions.urlencode(v_provider_order);

  begin
    select r.status, r.content
      into v_http_status, v_content
    from extensions.http_post(
      regexp_replace(trim(v_provider.base_url), '/+$', ''),
      v_body,
      'application/x-www-form-urlencoded'
    ) r;
  exception when others then
    return jsonb_build_object('status',false,'msg','Gagal menghubungi provider: '||sqlerrm);
  end;

  if coalesce(v_http_status,0) < 200 or coalesce(v_http_status,0) >= 300 then
    return jsonb_build_object('status',false,'msg','Provider HTTP '||coalesce(v_http_status,0)::text,'http_status',v_http_status);
  end if;

  begin
    v_json := coalesce(v_content,'{}')::jsonb;
  exception when others then
    return jsonb_build_object('status',false,'msg','Respons provider bukan JSON yang valid.','raw',left(coalesce(v_content,''),500));
  end;

  v_remote := lower(trim(coalesce(
    v_json->>'status',
    v_json->'data'->>'status',
    v_json->'order'->>'status',
    ''
  )));

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
    -- Never mark an order as failed just because the provider introduced an
    -- unknown status. Keep the current status until it is understood.
    return jsonb_build_object('status',true,'updated',false,'order_id',v_order.id::text,'provider_status',v_remote,'local_status',v_order.status);
  end if;

  if lower(coalesce(v_order.status::text,'')) is distinct from v_local then
    update public.orders
    set status=v_local
    where id::text=p_order_id;
    v_changed := true;
  end if;

  return jsonb_build_object(
    'status',true,
    'updated',v_changed,
    'order_id',v_order.id::text,
    'provider_order_id',v_provider_order,
    'provider_status',v_remote,
    'local_status',v_local,
    'http_status',v_http_status
  );
exception when others then
  return jsonb_build_object('status',false,'msg','Sinkronisasi gagal: '||sqlerrm);
end;
$fn$;

grant execute on function public.wsid_provider_order_status(text) to authenticated;

-- Sync all active orders belonging to the logged-in user.
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
  v_status text;
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

-- Add Partial styling/status semantics without changing existing status values.
-- The frontend maps provider Completed/Success -> success, Processing -> processing,
-- Partial -> partial, and Failed/Canceled/Error -> failed.
