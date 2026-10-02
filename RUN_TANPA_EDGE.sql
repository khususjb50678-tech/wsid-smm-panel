-- WSID: ganti Edge Function dengan SQL (jalankan SEKALI di Supabase > SQL Editor)
-- Pastikan RUN_ALL.sql sudah dijalankan lebih dulu.

create extension if not exists http with schema extensions;

-- Beri waktu lebih lama untuk Sync Services (default hanya 8 detik)
alter role authenticated set statement_timeout = '120s';

-- ====== Test koneksi & Sync layanan (khusus admin) ======
create or replace function public.provider_call(p_action text) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare p public.providers; resp extensions.http_response; j jsonb; n int; base text; hdr text;
begin
  if not public.is_admin() then return jsonb_build_object('status',false,'msg','Admin only'); end if;
  select * into p from public.providers where name='FAYUPEDIA' and is_active=true limit 1;
  if not found or coalesce(p.api_id,'')='' or coalesce(p.api_key,'')='' then
    return jsonb_build_object('status',false,'msg','API ID / API Key provider belum diisi atau provider tidak aktif.');
  end if;
  base := regexp_replace(coalesce(p.base_url,'https://fayupedia.id/api'),'/$','');
  hdr := 'api_id='||extensions.urlencode(p.api_id::varchar)||'&api_key='||extensions.urlencode(p.api_key::varchar);
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','60');
    perform extensions.http_set_curlopt('CURLOPT_CONNECTTIMEOUT','15');
    resp := extensions.http_post(base||'/'||case when p_action='balance' then 'balance' else 'services' end, hdr, 'application/x-www-form-urlencoded');
  exception when others then
    return jsonb_build_object('status',false,'msg','Tidak bisa menghubungi provider: '||sqlerrm);
  end;
  begin
    j := resp.content::jsonb;
  exception when others then
    return jsonb_build_object('status',false,'msg','Balasan provider bukan JSON (HTTP '||resp.status||'): '||left(coalesce(resp.content,''),150));
  end;
  if p_action='balance' then return j; end if;
  if coalesce(j->>'status','')<>'true' or jsonb_typeof(j->'services')<>'array' then
    return jsonb_build_object('status',false,'msg',coalesce(j->>'msg','Provider menolak permintaan: '||left(j::text,150)));
  end if;

  create temp table if not exists _wsid_src(pid text,nm text,typ text,cat text,price numeric,mn bigint,mx bigint,rf boolean,descr text) on commit drop;
  truncate _wsid_src;
  insert into _wsid_src
  select x.id, x.name, coalesce(nullif(x.type,''),'default'), coalesce(nullif(x.category,''),'Lainnya'),
         coalesce(nullif(x.price,'')::numeric,0), coalesce(nullif(x."min",'')::numeric::bigint,1), coalesce(nullif(x."max",'')::numeric::bigint,1),
         coalesce(x.refill,'') in ('true','1','t'), coalesce(x.description,'')
  from jsonb_to_recordset(j->'services') as x(id text,name text,category text,type text,price text,"min" text,"max" text,refill text,description text)
  where x.id is not null;

  insert into public.categories(name,slug)
  select distinct s.cat, trim(both '-' from regexp_replace(lower(s.cat),'[^a-z0-9]+','-','g'))||'-'||substr(md5(s.cat),1,5) from _wsid_src s
  on conflict (name) do nothing;

  insert into public.services(provider_service_id,name,type,category_id,category,provider_price,markup_type,markup_value,sale_price,min_qty,max_qty,refill,description,is_active)
  select s.pid,s.nm,s.typ,c.id,s.cat,s.price,p.default_markup_type,p.default_markup_value,
         case when p.default_markup_type='fixed' then s.price+p.default_markup_value else s.price*(1+p.default_markup_value/100) end,
         s.mn,s.mx,s.rf,s.descr,true
  from _wsid_src s join public.categories c on c.name=s.cat
  on conflict (provider_service_id) do update set
    name=excluded.name,type=excluded.type,category_id=excluded.category_id,category=excluded.category,
    provider_price=excluded.provider_price,
    sale_price=case when public.services.markup_type='fixed' then excluded.provider_price+public.services.markup_value else excluded.provider_price*(1+public.services.markup_value/100) end,
    min_qty=excluded.min_qty,max_qty=excluded.max_qty,refill=excluded.refill,description=excluded.description,is_active=true,updated_at=now();
  get diagnostics n = row_count;
  return jsonb_build_object('status',true,'msg','Services synced','count',n);
end$$;

-- ====== Kirim order user ke provider ======
create or replace function public.submit_order(p_order_id uuid) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare o public.orders; s public.services; p public.providers; resp extensions.http_response; j jsonb; body text; base text; ok boolean;
begin
  select * into o from public.orders where id=p_order_id and user_id=auth.uid() for update;
  if not found then return jsonb_build_object('status',false,'msg','Order tidak ditemukan'); end if;
  if o.provider_order_id is not null then return jsonb_build_object('status',true,'msg','Sudah dikirim','order',o.provider_order_id); end if;
  select * into s from public.services where id=o.service_id;
  select * into p from public.providers where name='FAYUPEDIA' and is_active=true limit 1;
  if not found or coalesce(p.api_id,'')='' or coalesce(p.api_key,'')='' then
    return jsonb_build_object('status',false,'msg','Provider API belum dikonfigurasi di Admin > Provider.');
  end if;
  base := regexp_replace(coalesce(p.base_url,'https://fayupedia.id/api'),'/$','');
  body := 'api_id='||extensions.urlencode(p.api_id::varchar)||'&api_key='||extensions.urlencode(p.api_key::varchar)
        ||'&service='||extensions.urlencode(s.provider_service_id::varchar)||'&target='||extensions.urlencode(o.target::varchar)||'&quantity='||o.quantity::text;
  if coalesce(o.comments,'')<>'' then body := body||'&comments='||extensions.urlencode(o.comments::varchar); end if;
  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','30');
    resp := extensions.http_post(base||'/order', body, 'application/x-www-form-urlencoded');
    j := resp.content::jsonb;
  exception when others then
    j := jsonb_build_object('status',false,'msg','Provider error: '||sqlerrm);
  end;
  ok := coalesce(j->>'status','') in ('true','1');
  if not ok then
    update public.orders set status='failed',provider_status='failed',error_message=coalesce(j->>'msg','Provider order failed'),updated_at=now() where id=o.id;
    update public.wallets set balance=balance+o.sale_total,updated_at=now() where user_id=o.user_id;
    insert into public.transactions(user_id,type,amount,reference_id,description) values(o.user_id,'refund',o.sale_total,o.id,'Refund order provider gagal');
    return jsonb_build_object('status',false,'msg',coalesce(j->>'msg','Provider order failed'));
  end if;
  update public.orders set provider_order_id=coalesce(j->>'order',''),provider_status='pending',status='processing',updated_at=now() where id=o.id;
  return jsonb_build_object('status',true,'order',j->>'order','msg',coalesce(j->>'msg','Order berhasil dikirim'));
end$$;

grant execute on function public.provider_call(text) to authenticated;
grant execute on function public.submit_order(uuid) to authenticated;
notify pgrst, 'reload schema';
notify pgrst, 'reload config';
