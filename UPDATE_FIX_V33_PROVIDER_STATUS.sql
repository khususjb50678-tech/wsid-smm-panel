-- WSID SMM PANEL V33 - PROVIDER STATUS SYNC (lebih tahan banting)
-- Jalankan SEKALI di Supabase > SQL Editor. Aman dijalankan ulang.
-- Hanya menyentuh sinkronisasi status order. Tidak mengubah order/saldo/deposit/Telegram.
--
-- Perbaikan dibanding V32:
--  1) http_set_curlopt dipisah: bila tidak tersedia, request TETAP dikirim.
--  2) Parameter dikirim lengkap (id, order, order_id, key, api_id, api_key, action=status)
--     karena tiap panel SMM beda nama parameter.
--  3) Mencoba 3 endpoint: <base>/status, <base>/order, <base>.
--  4) Parser respons lebih luas (data object / array / dikunci ID order).
--  5) UPDATE dibuat dinamis (tidak gagal bila kolom updated_at dll tidak ada).
--  6) Check constraint status lama yang menolak 'success'/'partial' dihapus.
--  7) Pesan error provider ditampilkan di detail riwayat (bukan diam-diam gagal).

-- 0) Hapus check constraint status lama yang tidak mengizinkan success/partial.
do $c$
declare r record;
begin
  for r in
    select con.conname, pg_get_constraintdef(con.oid) as def
    from pg_constraint con
    where con.conrelid='public.orders'::regclass
      and con.contype='c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    if r.def not ilike '%success%' or r.def not ilike '%partial%' then
      execute format('alter table public.orders drop constraint %I', r.conname);
    end if;
  end loop;
end
$c$;

-- 1) Pembaca status dari JSON respons provider.
create or replace function public.wsid_extract_provider_status(p_json jsonb, p_order text)
returns jsonb
language plpgsql
immutable
as $fn$
declare
  v_obj jsonb := null;
  v_status text := '';
  v_known text[] := array['pending','processing','in progress','in_progress','success','successful',
    'completed','complete','done','finished','partial','partially completed','cancel','cancelled',
    'canceled','failed','failure','error','rejected','reject','refund','refunded','waiting','queued','running'];
begin
  if p_json is null then return '{}'::jsonb; end if;

  if jsonb_typeof(p_json)='array' then
    if jsonb_array_length(p_json)>0 then v_obj := p_json->0; end if;
  elsif jsonb_typeof(p_json)='object' then
    if p_json ? p_order and jsonb_typeof(p_json->p_order)='object' then
      v_obj := p_json->p_order;
    elsif jsonb_typeof(p_json->'data')='object' then
      if jsonb_typeof(p_json->'data'->'order')='object' then v_obj := p_json->'data'->'order';
      else v_obj := p_json->'data'; end if;
    elsif jsonb_typeof(p_json->'data')='array' and jsonb_array_length(p_json->'data')>0 then
      v_obj := p_json->'data'->0;
    elsif jsonb_typeof(p_json->'order')='object' then
      v_obj := p_json->'order';
    else
      v_obj := p_json;
    end if;
  end if;

  if v_obj is null or jsonb_typeof(v_obj)<>'object' then return '{}'::jsonb; end if;

  v_status := lower(trim(coalesce(
    v_obj->>'status', v_obj->>'order_status', v_obj->>'state', v_obj->>'status_order', ''
  )));
  -- status=true/false di level pembungkus bukan status order.
  if v_status not in (select unnest(v_known)) then
    v_status := lower(trim(coalesce(p_json->>'order_status','')));
    if v_status not in (select unnest(v_known)) then v_status := ''; end if;
  end if;

  return jsonb_build_object(
    'status', v_status,
    'start_count', coalesce(v_obj->>'start_count', v_obj->>'start'),
    'remains', coalesce(v_obj->>'remains', v_obj->>'remain'),
    'charge', coalesce(v_obj->>'charge', v_obj->>'price')
  );
end;
$fn$;

-- 2) Cek status 1 order ke provider.
create or replace function public.wsid_provider_order_status(p_order_id text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_order record;
  v_row jsonb;
  v_provider record;
  v_provider_order text := '';
  v_k text;
  v_base text;
  v_urls text[];
  v_url text;
  v_body text;
  v_http integer := 0;
  v_content text := '';
  v_json jsonb;
  v_ext jsonb := '{}'::jsonb;
  v_remote text := '';
  v_local text := '';
  v_changed boolean := false;
  v_allowed boolean := false;
  v_last_msg text := '';
  v_last_raw text := '';
  v_last_url text := '';
  v_sets text[] := array[]::text[];
begin
  select o.* into v_order from public.orders o where o.id::text=p_order_id limit 1;
  if not found then
    return jsonb_build_object('status',false,'msg','Order tidak ditemukan.');
  end if;
  v_row := to_jsonb(v_order);

  select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')
         or v_order.user_id=auth.uid()
  into v_allowed;
  if not v_allowed then
    return jsonb_build_object('status',false,'msg','Akses ditolak.');
  end if;

  select * into v_provider from public.providers
  where name='FAYUPEDIA' order by updated_at desc nulls last limit 1;
  if not found or coalesce(v_provider.is_active,true)=false then
    return jsonb_build_object('status',false,'msg','Koneksi provider FAYUPEDIA tidak aktif.');
  end if;

  -- ID order di provider: coba beberapa nama kolom yang umum dipakai.
  foreach v_k in array array['provider_order_id','provider_order','provider_trx_id','provider_id',
      'external_order_id','external_id','provider_reference','provider_ref','trx_id'] loop
    if coalesce(trim(v_row->>v_k),'')<>'' then
      v_provider_order := trim(v_row->>v_k);
      exit;
    end if;
  end loop;
  if v_provider_order='' then
    return jsonb_build_object('status',false,
      'msg','Provider order ID kosong di tabel orders (pesanan ini belum tercatat punya ID provider).');
  end if;

  if coalesce(trim(v_provider.base_url),'')='' or coalesce(trim(v_provider.api_key),'')='' then
    return jsonb_build_object('status',false,'msg','Base URL/API key provider belum lengkap.');
  end if;

  v_base := regexp_replace(trim(v_provider.base_url),'/+$','');
  v_base := regexp_replace(v_base,'/(order|status)$','');
  v_urls := array[v_base||'/status', v_base||'/order', v_base];

  v_body := 'api_id='||extensions.urlencode(trim(coalesce(v_provider.api_id::text,'')))
         ||'&api_key='||extensions.urlencode(trim(v_provider.api_key))
         ||'&key='||extensions.urlencode(trim(v_provider.api_key))
         ||'&action=status'
         ||'&id='||extensions.urlencode(v_provider_order)
         ||'&order='||extensions.urlencode(v_provider_order)
         ||'&order_id='||extensions.urlencode(v_provider_order);

  foreach v_url in array v_urls loop
    v_http := 0; v_content := ''; v_json := null;
    v_last_url := v_url;
    begin
      begin
        perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','15');
      exception when others then null;
      end;
      select r.status, r.content into v_http, v_content
      from extensions.http_post(v_url, v_body, 'application/x-www-form-urlencoded') r;
    exception when others then
      v_http := 0; v_content := ''; v_last_msg := sqlerrm;
    end;

    v_last_raw := left(coalesce(v_content,''),200);

    begin
      v_json := coalesce(nullif(v_content,''),'{}')::jsonb;
    exception when others then
      v_json := null;
    end;

    if v_json is not null then
      v_ext := public.wsid_extract_provider_status(v_json, v_provider_order);
      v_remote := coalesce(v_ext->>'status','');
      if v_remote<>'' then exit; end if;
      if jsonb_typeof(v_json)='object' then
        v_last_msg := coalesce(nullif(v_json->>'msg',''), nullif(v_json->>'message',''),
                               nullif(v_json->>'error',''), v_last_msg);
      end if;
    end if;
  end loop;

  if v_remote='' then
    return jsonb_build_object('status',false,'updated',false,
      'msg', coalesce(nullif(v_last_msg,''),'Provider tidak mengembalikan status order.')
             ||' [HTTP '||v_http||' @ '||v_last_url||'] '||v_last_raw,
      'provider_order_id',v_provider_order,'http_status',v_http,'endpoint',v_last_url);
  end if;

  if v_remote in ('completed','complete','success','successful','done','finished') then v_local:='success';
  elsif v_remote in ('processing','in progress','in_progress','running','working') then v_local:='processing';
  elsif v_remote in ('pending','waiting','queued','queue') then v_local:='pending';
  elsif v_remote in ('partial','partially completed','partially_complete') then v_local:='partial';
  elsif v_remote in ('cancel','canceled','cancelled','failed','failure','error','rejected','reject','refunded','refund') then v_local:='failed';
  else
    return jsonb_build_object('status',true,'updated',false,'order_id',v_order.id::text,
      'provider_order_id',v_provider_order,'provider_status',v_remote,'local_status',v_order.status);
  end if;

  -- UPDATE dinamis: hanya kolom yang benar-benar ada.
  if lower(coalesce(v_row->>'status','')) is distinct from v_local then
    v_sets := v_sets||format('status=%L',v_local); v_changed:=true;
  end if;
  if v_row ? 'provider_status' and lower(coalesce(v_row->>'provider_status','')) is distinct from v_remote then
    v_sets := v_sets||format('provider_status=%L',v_remote); v_changed:=true;
  end if;
  if v_row ? 'start_count' and coalesce(v_ext->>'start_count','') ~ '^[0-9]+$' then
    v_sets := v_sets||format('start_count=%s',v_ext->>'start_count');
  end if;
  if v_row ? 'remains' and coalesce(v_ext->>'remains','') ~ '^[0-9]+$' then
    v_sets := v_sets||format('remains=%s',v_ext->>'remains');
  end if;
  if v_changed and v_row ? 'updated_at' then
    v_sets := v_sets||'updated_at=now()';
  end if;

  if array_length(v_sets,1)>0 then
    execute 'update public.orders set '||array_to_string(v_sets,', ')||' where id::text='||quote_literal(p_order_id);
  end if;

  return jsonb_build_object('status',true,'updated',v_changed,'order_id',v_order.id::text,
    'provider_order_id',v_provider_order,'provider_status',v_remote,'local_status',v_local);
exception when others then
  return jsonb_build_object('status',false,'msg','Sinkronisasi gagal: '||sqlerrm,
    'provider_order_id',v_provider_order);
end;
$fn$;

grant execute on function public.wsid_provider_order_status(text) to authenticated;

-- 3) Sinkron semua order milik user yang belum final.
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
  v_err text := '';
begin
  if auth.uid() is null then
    return jsonb_build_object('status',false,'msg','Belum login.');
  end if;

  for r in
    select o.id from public.orders o
    where o.user_id=auth.uid()
      and lower(coalesce(o.status::text,'')) not in
        ('success','completed','complete','failed','error','cancelled','canceled','rejected','partial','refunded')
    order by o.created_at desc
    limit 15
  loop
    v_checked := v_checked+1;
    x := public.wsid_provider_order_status(r.id::text);
    if coalesce((x->>'status')::boolean,false) then
      if coalesce((x->>'updated')::boolean,false) then v_updated := v_updated+1; end if;
    else
      v_failed := v_failed+1;
      v_err := coalesce(x->>'msg','');
    end if;
  end loop;

  return jsonb_build_object('status',true,'checked',v_checked,'updated',v_updated,
                            'failed',v_failed,'last_error',v_err);
end;
$fn$;

grant execute on function public.sync_my_order_statuses() to authenticated;

notify pgrst, 'reload schema';
