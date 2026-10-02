-- ============================================================
-- WSID SMM PANEL FINAL V21
-- Update final: Deposit fee + pembayaran + Developer + Reset.
-- TARIK SALDO DIBATALKAN.
-- Jalankan SEKALI di Supabase SQL Editor.
-- ============================================================

-- 1. Setting yang dibutuhkan versi final.
insert into public.panel_settings(key,value) values
  ('gopay_number',''),
  ('gopay_name','Witama Store.ID'),
  ('deposit_fee_percent','0.7'),
  ('developer_name','Witama Yuliananta'),
  ('developer_bio','Developer dan pembuat WSID SMM PANEL. Website ini dikembangkan dan dikelola untuk kebutuhan Witama Store.ID.'),
  ('developer_logo_url',''),
  ('support_whatsapp',''),
  ('support_telegram',''),
  ('support_instagram',''),
  ('monitoring_website_url','')
on conflict(key) do nothing;

-- Hapus hanya setting tarik saldo lama. Data/tabel lain tidak disentuh.
delete from public.panel_settings
where key in ('withdrawal_fee','withdrawal_min');

-- 2. Kolom deposit untuk biaya admin dan metode pembayaran.
alter table public.deposits
  add column if not exists fee_amount numeric(18,2) not null default 0;

alter table public.deposits
  add column if not exists payment_total numeric(18,2) not null default 0;

alter table public.deposits
  add column if not exists payment_method text;

update public.deposits
set payment_total=amount
where payment_total=0 and amount>0;

-- 3. Bucket untuk QRIS + logo developer.
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

-- 4. Bucket bukti deposit dipastikan ada.
insert into storage.buckets (id,name,public)
values ('deposit-proofs','deposit-proofs',false)
on conflict (id) do nothing;

drop policy if exists deposit_proofs_insert_own on storage.objects;
create policy deposit_proofs_insert_own on storage.objects
for insert to authenticated
with check (
  bucket_id='deposit-proofs'
  and (storage.foldername(name))[1]=auth.uid()::text
);

drop policy if exists deposit_proofs_read_admin_or_own on storage.objects;
create policy deposit_proofs_read_admin_or_own on storage.objects
for select to authenticated
using (
  bucket_id='deposit-proofs'
  and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);

-- 5. Request deposit.
-- Fee dihitung di server berdasarkan panel_settings, bukan browser.
create or replace function public.request_deposit(
  p_amount numeric,
  p_proof_path text,
  p_method text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $wsid_request_deposit$
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
  if v_user is null then
    raise exception 'Silakan login terlebih dahulu';
  end if;

  if v_amount < 2000 then
    raise exception 'Minimal deposit adalah Rp2.000';
  end if;

  if v_path='' then
    raise exception 'Bukti pembayaran wajib diunggah';
  end if;

  if split_part(v_path,'/',1) <> v_user::text then
    raise exception 'Bukti pembayaran tidak valid';
  end if;

  if v_method not in ('dana','gopay','qris') then
    raise exception 'Metode pembayaran tidak valid';
  end if;

  select greatest(0,coalesce(value::numeric,0))
    into v_fee_percent
  from public.panel_settings
  where key='deposit_fee_percent';

  v_fee_percent := coalesce(v_fee_percent,0.7);
  v_fee := round(v_amount * v_fee_percent / 100,0);
  v_total := v_amount + v_fee;

  insert into public.deposits(
    user_id,
    amount,
    proof_path,
    status,
    fee_amount,
    payment_total,
    payment_method
  ) values (
    v_user,
    v_amount,
    v_path,
    'pending',
    v_fee,
    v_total,
    v_method
  ) returning id into v_id;

  return jsonb_build_object(
    'status',true,
    'id',v_id,
    'amount',v_amount,
    'fee_amount',v_fee,
    'payment_total',v_total,
    'fee_percent',v_fee_percent
  );
end;
$wsid_request_deposit$;

grant execute on function public.request_deposit(numeric,text,text) to authenticated;

-- 6. Reset Admin.
-- Semua DELETE sengaja memakai WHERE agar tidak memicu error
-- "DELETE requires a WHERE clause" pada editor/linter tertentu.
create or replace function public.admin_reset_panel_data(p_target text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $wsid_reset_v21$
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
    update public.wallets
       set balance=0,
           updated_at=now()
     where true;
    return jsonb_build_object('status',true,'target',v_target,'message','Semua data aktivitas berhasil direset. Akun user tetap ada.');

  else
    raise exception 'Target reset tidak dikenal: %',v_target;
  end if;
end;
$wsid_reset_v21$;

grant execute on function public.admin_reset_panel_data(text) to authenticated;



-- 7. Link tombol pada pesan monitoring Telegram.
-- Tombol diarahkan ke WEBSITE PANEL yang diatur Admin, bukan ke bot Telegram.
-- Jika URL kosong/tidak valid, notifikasi tetap terkirim tanpa tombol.
create or replace function public.wsid_queue_telegram(p_chat text, p_text text)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $wsid_queue_telegram_v21$
declare
  v_token text;
  v_url text;
  v_body jsonb;
  v_headers jsonb := jsonb_build_object('Content-Type','application/json');
begin
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='TOKEN_BOT_TELEGRAM'
  limit 1;

  if coalesce(trim(p_chat),'')='' or coalesce(trim(v_token),'')='' then
    return;
  end if;

  select trim(coalesce(value,'')) into v_url
  from public.panel_settings
  where key='monitoring_website_url'
  limit 1;

  v_body := jsonb_build_object(
    'chat_id', trim(p_chat),
    'text', coalesce(p_text,''),
    'parse_mode', 'HTML',
    'disable_web_page_preview', true
  );

  if coalesce(v_url,'') ~* '^https?://[^[:space:]]+$' then
    v_body := v_body || jsonb_build_object(
      'reply_markup',
      jsonb_build_object(
        'inline_keyboard',
        jsonb_build_array(
          jsonb_build_array(
            jsonb_build_object('text','🌐 Buka Website WSID','url',v_url)
          )
        )
      )
    );
  end if;

  begin
    execute 'select extensions.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.telegram.org/bot'||v_token||'/sendMessage', v_body, v_headers;
  exception when undefined_function then
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using 'https://api.telegram.org/bot'||v_token||'/sendMessage', v_body, v_headers;
  end;
exception when others then
  -- Jangan menggagalkan transaksi panel hanya karena Telegram bermasalah.
  return;
end;
$wsid_queue_telegram_v21$;

grant execute on function public.wsid_queue_telegram(text,text) to authenticated;

notify pgrst, 'reload schema';
