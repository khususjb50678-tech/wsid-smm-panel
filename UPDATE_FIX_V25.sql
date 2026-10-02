-- ============================================================
-- WSID SMM PANEL V25 - FIX DEPOSIT + ORDER + PAYMENT LOGO
-- Bisa dijalankan ulang di Supabase SQL Editor; script dibuat idempotent.
-- Tidak menghapus data user, saldo, order, atau deposit lama.
-- ============================================================

-- 1) Pastikan setting logo pembayaran tersedia.
insert into public.panel_settings(key,value) values
  ('dana_logo_url',''),
  ('gopay_logo_url',''),
  ('qris_logo_url','')
on conflict(key) do nothing;

-- 2) Pastikan kolom deposit versi terbaru tersedia.
alter table public.deposits add column if not exists fee_amount numeric(18,2) not null default 0;
alter table public.deposits add column if not exists payment_total numeric(18,2) not null default 0;
alter table public.deposits add column if not exists payment_method text;

-- 3) Pastikan bucket bukti deposit tersedia.
insert into storage.buckets (id,name,public)
values ('deposit-proofs','deposit-proofs',false)
on conflict (id) do nothing;

-- 4) FIX UTAMA:
-- Jangan gunakan (storage.foldername(name))[1].
-- Pada project tertentu foldername() dapat dikembalikan sebagai text,
-- sehingga PostgreSQL memunculkan:
-- "cannot subscript type text because it does not support subscripting".
-- Kita ambil folder pertama dengan split_part() yang selalu aman untuk text.

drop policy if exists deposit_proofs_insert on storage.objects;
drop policy if exists deposit_proofs_insert_own on storage.objects;
drop policy if exists deposit_proofs_read on storage.objects;
drop policy if exists deposit_proofs_read_admin_or_own on storage.objects;

drop policy if exists dep_proofs_insert on storage.objects;
drop policy if exists dep_proofs_read on storage.objects;

-- Hapus juga policy V24 jika script pernah dijalankan sebagian.
-- Ini membuat patch aman dijalankan ulang tanpa error 42710.
drop policy if exists deposit_proofs_insert_v24 on storage.objects;
drop policy if exists deposit_proofs_read_v24 on storage.objects;

create policy deposit_proofs_insert_v24 on storage.objects
for insert to authenticated
with check (
  bucket_id='deposit-proofs'
  and split_part(name,'/',1)=auth.uid()::text
);

create policy deposit_proofs_read_v24 on storage.objects
for select to authenticated
using (
  bucket_id='deposit-proofs'
  and (split_part(name,'/',1)=auth.uid()::text or public.is_admin())
);

-- 5) Request deposit versi aman.
create or replace function public.request_deposit(
  p_amount numeric,
  p_proof_path text,
  p_method text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_user uuid := auth.uid();
  v_amount numeric(18,2) := round(coalesce(p_amount,0),0);
  v_fee_percent numeric(18,4);
  v_fee numeric(18,2);
  v_total numeric(18,2);
  v_method text := lower(trim(coalesce(p_method,'')));
  v_path text := trim(coalesce(p_proof_path,''));
  v_id uuid;
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if v_amount < 2000 then raise exception 'Minimal deposit adalah Rp2.000'; end if;
  if v_path='' then raise exception 'Bukti pembayaran wajib diunggah'; end if;
  if split_part(v_path,'/',1) <> v_user::text then raise exception 'Bukti pembayaran tidak valid'; end if;
  if v_method not in ('dana','gopay','qris') then raise exception 'Metode pembayaran tidak valid'; end if;

  select greatest(0,coalesce(value::numeric,0)) into v_fee_percent
  from public.panel_settings where key='deposit_fee_percent';
  v_fee_percent := coalesce(v_fee_percent,0.7);
  v_fee := round(v_amount*v_fee_percent/100,0);
  v_total := v_amount+v_fee;

  insert into public.deposits(user_id,amount,proof_path,status,fee_amount,payment_total,payment_method)
  values(v_user,v_amount,v_path,'pending',v_fee,v_total,v_method)
  returning id into v_id;

  return jsonb_build_object(
    'status',true,
    'id',v_id,
    'amount',v_amount,
    'fee_amount',v_fee,
    'payment_total',v_total,
    'fee_percent',v_fee_percent
  );
end;
$fn$;

grant execute on function public.request_deposit(numeric,text,text) to authenticated;

-- 6) Create order versi bersih.
-- Tidak menggunakan subscripting pada text.
create or replace function public.create_order(
  p_service_id uuid,
  p_target text,
  p_quantity bigint
)
returns uuid
language plpgsql
security definer
set search_path=public,extensions
as $fn$
declare
  s public.services;
  bal numeric;
  total numeric;
  pc numeric;
  oid uuid;
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Silakan login terlebih dahulu'; end if;
  if coalesce(trim(p_target),'')='' then raise exception 'Target wajib diisi'; end if;

  select * into s from public.services where id=p_service_id and is_active=true;
  if not found then raise exception 'Service tidak tersedia'; end if;
  if p_quantity < s.min_qty or p_quantity > s.max_qty then raise exception 'Jumlah di luar batas'; end if;

  total=round(s.sale_price/1000*p_quantity,2);
  pc=round(s.provider_price/1000*p_quantity,2);

  select balance into bal from public.wallets where user_id=v_user for update;
  if bal is null then raise exception 'Wallet user tidak ditemukan'; end if;
  if bal < total then raise exception 'Saldo tidak mencukupi'; end if;

  update public.wallets
  set balance=balance-total,updated_at=now()
  where user_id=v_user;

  insert into public.orders(user_id,service_id,target,quantity,sale_total,provider_cost,profit)
  values(v_user,s.id,trim(p_target),p_quantity,total,pc,total-pc)
  returning id into oid;

  insert into public.transactions(user_id,type,amount,reference_id,description)
  values(v_user,'order',-total,oid,'Order layanan');

  return oid;
end;
$fn$;

grant execute on function public.create_order(uuid,text,bigint) to authenticated;

-- 7) Submit order ke FAYUPEDIA.
-- Tetap menggunakan format API yang sama, tetapi dibuat defensif
-- agar kegagalan provider tidak membuat saldo user hilang.
create or replace function public.submit_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $fn$
declare
  o public.orders;
  s public.services;
  p public.providers;
  resp extensions.http_response;
  j jsonb;
  body text;
  base text;
  ok boolean;
  v_user uuid := auth.uid();
begin
  if v_user is null then return jsonb_build_object('status',false,'msg','Silakan login terlebih dahulu'); end if;

  select * into o from public.orders
  where id=p_order_id and user_id=v_user
  for update;

  if not found then return jsonb_build_object('status',false,'msg','Order tidak ditemukan'); end if;
  if o.provider_order_id is not null then
    return jsonb_build_object('status',true,'msg','Sudah dikirim','order',o.provider_order_id);
  end if;

  select * into s from public.services where id=o.service_id;
  if not found then
    update public.orders set status='failed',error_message='Service tidak ditemukan',updated_at=now() where id=o.id;
    update public.wallets set balance=balance+o.sale_total,updated_at=now() where user_id=o.user_id;
    insert into public.transactions(user_id,type,amount,reference_id,description)
    values(o.user_id,'refund',o.sale_total,o.id,'Refund pesanan - service tidak ditemukan');
    return jsonb_build_object('status',false,'msg','Service tidak ditemukan');
  end if;

  select * into p from public.providers where name='FAYUPEDIA' and is_active=true limit 1;
  if not found or coalesce(p.api_id,'')='' or coalesce(p.api_key,'')='' then
    return jsonb_build_object('status',false,'msg','Koneksi layanan belum dikonfigurasi di Admin > Koneksi.');
  end if;

  base := regexp_replace(coalesce(p.base_url,'https://fayupedia.id/api'),'/$','');
  body := 'api_id='||extensions.urlencode(p.api_id::varchar)
       ||'&api_key='||extensions.urlencode(p.api_key::varchar)
       ||'&service='||extensions.urlencode(s.provider_service_id::varchar)
       ||'&target='||extensions.urlencode(o.target::varchar)
       ||'&quantity='||o.quantity::text;

  if coalesce(o.comments,'')<>'' then
    body := body||'&comments='||extensions.urlencode(o.comments::varchar);
  end if;

  begin
    perform extensions.http_set_curlopt('CURLOPT_TIMEOUT','30');
    resp := extensions.http_post(base||'/order',body,'application/x-www-form-urlencoded');
    j := coalesce(resp.content::jsonb,jsonb_build_object('status',false,'msg','Respons provider kosong'));
  exception when others then
    j := jsonb_build_object('status',false,'msg','Koneksi provider gagal: '||sqlerrm);
  end;

  ok := lower(coalesce(j->>'status','')) in ('true','1','success','successful');

  if not ok then
    update public.orders
    set status='failed',provider_status='failed',error_message=coalesce(j->>'msg','Pengiriman layanan gagal'),updated_at=now()
    where id=o.id;

    update public.wallets set balance=balance+o.sale_total,updated_at=now() where user_id=o.user_id;
    insert into public.transactions(user_id,type,amount,reference_id,description)
    values(o.user_id,'refund',o.sale_total,o.id,'Refund pesanan gagal');

    return jsonb_build_object('status',false,'msg',coalesce(j->>'msg','Pengiriman layanan gagal'));
  end if;

  update public.orders
  set provider_order_id=coalesce(j->>'order',j->>'id',''),
      provider_status='pending',status='processing',updated_at=now()
  where id=o.id;

  return jsonb_build_object(
    'status',true,
    'order',coalesce(j->>'order',j->>'id',''),
    'msg',coalesce(j->>'msg','Order berhasil dikirim')
  );
end;
$fn$;

grant execute on function public.submit_order(uuid) to authenticated;

-- 8) Pastikan setting baru bisa dibaca frontend.
notify pgrst, 'reload schema';
notify pgrst, 'reload config';

-- ============================================================
-- SELESAI
-- Setelah Run sukses:
-- 1. Refresh website.
-- 2. Coba deposit lagi.
-- 3. Coba order sosmed lagi.
-- 4. Admin > Settings sekarang punya upload logo DANA, GoPay, QRIS.
-- ============================================================
