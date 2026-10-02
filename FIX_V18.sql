-- WSID SMM PANEL V18
-- Jalankan file ini SEKALI di Supabase SQL Editor.
-- Tidak menghapus akun user, layanan, order, atau deposit saat dijalankan.

-- 1) Setting baru untuk GoPay + Developer + Customer Service
insert into public.panel_settings(key,value) values
('gopay_number',''),
('gopay_name','Witama Store.ID'),
('developer_name','Witama Yuliananta'),
('developer_bio','Developer dan pembuat WSID SMM PANEL. Website ini dikembangkan dan dikelola untuk kebutuhan Witama Store.ID.'),
('developer_logo_url',''),
('support_whatsapp',''),
('support_telegram',''),
('support_instagram','')
on conflict(key) do nothing;

-- 2) Bucket publik untuk QRIS + logo developer
insert into storage.buckets (id,name,public)
values ('panel-assets','panel-assets',true)
on conflict (id) do update set public=true;

drop policy if exists panel_assets_admin_insert on storage.objects;
create policy panel_assets_admin_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='panel-assets'
  and public.is_admin()
);

drop policy if exists panel_assets_admin_update on storage.objects;
create policy panel_assets_admin_update on storage.objects
for update to authenticated
using (
  bucket_id='panel-assets'
  and public.is_admin()
)
with check (
  bucket_id='panel-assets'
  and public.is_admin()
);

drop policy if exists panel_assets_admin_delete on storage.objects;
create policy panel_assets_admin_delete on storage.objects
for delete to authenticated
using (
  bucket_id='panel-assets'
  and public.is_admin()
);

drop policy if exists panel_assets_public_read on storage.objects;
create policy panel_assets_public_read on storage.objects
for select to public
using (bucket_id='panel-assets');

-- 3) Reset diperbaiki.
-- Semua DELETE memakai WHERE true agar lolos SQL Editor yang mengharuskan WHERE.
create or replace function public.admin_reset_panel_data(p_target text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $wsid_reset$
declare
  v_target text := lower(trim(coalesce(p_target,'')));
  v_count bigint := 0;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  if v_target='profit' then
    update public.orders
       set profit=0,
           updated_at=now()
     where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua profit order berhasil direset menjadi Rp0.');

  elsif v_target='balance' then
    update public.wallets
       set balance=0,
           updated_at=now()
     where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua saldo user berhasil direset menjadi Rp0.');

  elsif v_target='orders' then
    delete from public.orders where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua riwayat order berhasil dihapus.');

  elsif v_target='deposits' then
    delete from public.deposits where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua riwayat deposit berhasil dihapus.');

  elsif v_target='transactions' then
    delete from public.transactions where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua transaksi berhasil dihapus.');

  elsif v_target='logins' then
    delete from public.login_events where true;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua aktivitas login berhasil dihapus.');

  elsif v_target='all_activity' then
    delete from public.transactions where true;
    delete from public.deposits where true;
    delete from public.orders where true;
    delete from public.login_events where true;
    update public.wallets set balance=0,updated_at=now() where true;
    return jsonb_build_object('status',true,'target',v_target,'message','Semua data aktivitas berhasil direset. Akun user tetap ada.');

  else
    raise exception 'Target reset tidak dikenal: %',v_target;
  end if;
end;
$wsid_reset$;

grant execute on function public.admin_reset_panel_data(text) to authenticated;

notify pgrst,'reload schema';
