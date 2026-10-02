-- WSID SMM PANEL V14 - Telegram Monitoring Design
-- SQL ONLY. Tidak memakai Edge Function.
-- Tujuan: ubah notifikasi Telegram agar tampil seperti gaya monitoring pada referensi:
-- - Judul hijau/tebal di luar quote ditangani oleh nama chat/channel Telegram.
-- - Isi utama memakai blockquote Telegram.
-- - Font isi memakai italic + bold pada bagian penting.
-- - Separator rapi.
-- - Tidak ada HTML mentah yang terlihat.
-- - Emoji dibangun memakai chr() agar tidak berubah menjadi teks "ðŸ..." karena masalah encoding.

-- Helper karakter emoji aman UTF-8.
create or replace function public.wsid_emoji(p_codepoint integer)
returns text
language sql
immutable
as $$
  select chr(p_codepoint);
$$;

-- Helper untuk format angka rupiah.
create or replace function public.wsid_rupiah(p_amount numeric)
returns text
language sql
immutable
as $$
  select 'Rp '||to_char(coalesce(p_amount,0),'FM999G999G999G999G990');
$$;

-- Helper notifikasi Telegram.
-- Semua pesan dikirim dalam parse_mode HTML dan menggunakan blockquote.
create or replace function public.wsid_notify_channel(p_text text)
returns void
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_bot text;
  v_request bigint;
  v_text text:=p_text;
begin
  select nullif(trim(value),'') into v_chat
  from public.panel_settings
  where key='telegram_notify_chat_id'
  limit 1;

  if coalesce(v_chat,'')='' then
    select nullif(trim(chat_id),'') into v_chat
    from public.telegram_config
    where id=1 limit 1;
  end if;

  if coalesce(v_chat,'')='' then
    select nullif(trim(value),'') into v_chat
    from public.panel_settings
    where key='telegram_chat_id'
    limit 1;
  end if;

  if coalesce(v_chat,'')='' then return; end if;

  select nullif(trim(value),'') into v_bot
  from public.panel_settings
  where key='telegram_bot_username'
  limit 1;

  if coalesce(v_bot,'')<>'' and position('https://t.me/' in v_text)=0 then
    v_text:=v_text||E'\n\n🔗 <a href="https://t.me/'||replace(v_bot,'@','')||'">Buka Bot WSID</a>';
  end if;

  begin
    v_request:=public.wsid_queue_telegram(v_chat,v_text);
  exception when others then
    raise warning 'WSID Telegram notification gagal: %',sqlerrm;
  end;
end;
$$;

-- TEST TELEGRAM dengan desain yang sama.
create or replace function public.test_telegram_deposit_notification()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_req bigint;
  e_bell text:=chr(128276);
  e_spark text:=chr(10024);
  e_black text:=chr(128420);
  e_link text:=chr(128279);
begin
  if not public.is_admin() then raise exception 'Akses ditolak'; end if;

  select nullif(trim(value),'') into v_chat
  from public.panel_settings where key='telegram_notify_chat_id' limit 1;

  if coalesce(v_chat,'')='' then
    select nullif(trim(chat_id),'') into v_chat
    from public.telegram_config where id=1 limit 1;
  end if;

  if coalesce(v_chat,'')='' then
    return jsonb_build_object('status',false,'msg','Channel/Grup Notifikasi belum diisi.');
  end if;

  v_req:=public.wsid_queue_telegram(
    v_chat,
    '<b>WS.ID | ALL MONITORING '||e_spark||'</b>'||E'\n\n'
    ||'<blockquote><b>'||e_bell||' TEST NOTIFIKASI WSID SMM PANEL</b>'||E'\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||'<i>'||e_spark||' Channel / Grup berhasil terhubung.</i>'||E'\n\n'
    ||'<i>Semua notifikasi user baru, login, deposit, order, status dan saldo akan dikirim dengan format monitoring ini.</i>'||E'\n\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||'<b>'||e_black||' Witama Store. ID</b></blockquote>'
  );

  return jsonb_build_object('status',true,'msg','Tes Telegram berhasil diantrikan. Request ID: '||v_req::text);
exception when others then
  return jsonb_build_object('status',false,'msg',sqlerrm);
end;
$$;

grant execute on function public.test_telegram_deposit_notification() to authenticated;

-- USER BARU
create or replace function public.wsid_notify_new_user()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_bot text; v_link text;
  e_drop text:=chr(128308); e_star text:=chr(10024); e_person text:=chr(128100);
  e_id text:=chr(127463); e_link text:=chr(128279); e_party text:=chr(127881); e_black text:=chr(128420);
begin
  select nullif(trim(value),'') into v_bot from public.panel_settings where key='telegram_bot_username' limit 1;
  v_link:=case when coalesce(v_bot,'')<>'' then E'\n'||e_link||' <a href="https://t.me/'||replace(v_bot,'@','')||'">Buka Bot WSID</a>' else '' end;

  perform public.wsid_notify_channel(
    '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
    ||'<blockquote><b>'||e_drop||' Fix Merah • New User</b>'||E'\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||'<i>'||e_star||' User Baru Terdaftar</i>'||E'\n\n'
    ||e_person||' <i>Nama:</i> <b>'||replace(coalesce(new.full_name,'Member'),'&','&amp;')||'</b>'||E'\n'
    ||e_id||' <i>ID:</i> <code>'||new.id::text||'</code>'||E'\n'
    ||e_link||' <i>Email:</i> <code>'||replace(coalesce(new.email,'-'),'&','&amp;')||'</code>'||E'\n\n'
    ||e_party||' <i>Selamat Bergabung!</i>'||E'\n\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||e_black||' <b>Witama Store. ID</b></blockquote>'
    ||v_link
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_new_user_telegram on public.profiles;
create trigger trg_wsid_new_user_telegram after insert on public.profiles for each row execute function public.wsid_notify_new_user();

-- LOGIN
create or replace function public.wsid_notify_login()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_bot text; v_link text;
  e_green text:=chr(128994); e_star text:=chr(10024); e_person text:=chr(128100); e_id text:=chr(127463); e_link text:=chr(128279); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  select nullif(trim(value),'') into v_bot from public.panel_settings where key='telegram_bot_username' limit 1;
  v_link:=case when coalesce(v_bot,'')<>'' then E'\n'||e_link||' <a href="https://t.me/'||replace(v_bot,'@','')||'">Buka Bot WSID</a>' else '' end;

  perform public.wsid_notify_channel(
    '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
    ||'<blockquote><b>'||e_green||' User • Login</b>'||E'\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||'<i>'||e_star||' User Login ke Website</i>'||E'\n\n'
    ||e_person||' <i>Nama:</i> <b>'||replace(coalesce(new.full_name,'Member'),'&','&amp;')||'</b>'||E'\n'
    ||e_id||' <i>ID:</i> <code>'||new.user_id::text||'</code>'||E'\n'
    ||e_clock||' <i>Waktu:</i> <b>'||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI:SS')||' WIB</b>'||E'\n\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||e_black||' <b>Witama Store. ID</b></blockquote>'
    ||v_link
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_login_telegram on public.login_events;
create trigger trg_wsid_login_telegram after insert on public.login_events for each row execute function public.wsid_notify_login();

-- DEPOSIT BARU
create or replace function public.wsid_send_deposit_telegram()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text; v_email text; v_money text;
  e_blood text:=chr(128308); e_star text:=chr(10024); e_person text:=chr(128100); e_money text:=chr(128176); e_id text:=chr(127470); e_pin text:=chr(128204); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  if new.status <> 'pending' then return new; end if;
  select coalesce(full_name,'User'),coalesce(email,'-') into v_name,v_email from public.profiles where id=new.user_id;
  v_money:=public.wsid_rupiah(new.amount);
  perform public.wsid_notify_channel(
    '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
    ||'<blockquote><b>'||e_blood||' Deposit Baru • Menunggu ACC</b>'||E'\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||'<i>'||e_star||' Pengajuan Deposit</i>'||E'\n\n'
    ||e_person||' <i>User:</i> <b>'||replace(v_name,'&','&amp;')||'</b>'||E'\n'
    ||e_money||' <i>Nominal:</i> <b>'||v_money||'</b>'||E'\n'
    ||e_id||' <i>ID:</i> <code>DEP-'||(upper(replace(new.id::text,'-','')))[1:10]||'</code>'||E'\n'
    ||e_pin||' <i>Status:</i> <b>Menunggu ACC Admin</b>'||E'\n'
    ||e_clock||' <i>Waktu:</i> <b>'||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB</b>'||E'\n\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||e_black||' <b>Witama Store. ID</b></blockquote>'
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_deposit_telegram on public.deposits;
create trigger trg_wsid_deposit_telegram after insert on public.deposits for each row execute function public.wsid_send_deposit_telegram();

-- STATUS DEPOSIT
create or replace function public.wsid_notify_deposit_status()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text; v_money text; v_status text;
  e_ok text:=chr(9989); e_no text:=chr(10060); e_star text:=chr(10024); e_person text:=chr(128100); e_money text:=chr(128176); e_id text:=chr(127470); e_pin text:=chr(128204); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  if tg_op='UPDATE' and old.status is distinct from new.status then
    select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
    v_money:=public.wsid_rupiah(new.amount);
    v_status:=case when new.status='approved' then e_ok||' Disetujui / ACC' when new.status='rejected' then e_no||' Ditolak' else new.status end;
    perform public.wsid_notify_channel(
      '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
      ||'<blockquote><b>'||e_money||' Deposit • Status Update</b>'||E'\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_person||' <i>User:</i> <b>'||replace(v_name,'&','&amp;')||'</b>'||E'\n'
      ||e_money||' <i>Nominal:</i> <b>'||v_money||'</b>'||E'\n'
      ||e_id||' <i>ID:</i> <code>DEP-'||(upper(replace(new.id::text,'-','')))[1:10]||'</code>'||E'\n'
      ||e_pin||' <i>Status:</i> <b>'||v_status||'</b>'||E'\n'
      ||e_clock||' <i>Waktu:</i> <b>'||to_char(coalesce(new.reviewed_at,now()) at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB</b>'||E'\n\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_black||' <b>Witama Store. ID</b></blockquote>'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_deposit_status_telegram on public.deposits;
create trigger trg_wsid_deposit_status_telegram after update of status on public.deposits for each row execute function public.wsid_notify_deposit_status();

-- ORDER BARU
create or replace function public.wsid_notify_order()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text; v_service text;
  e_blue text:=chr(128309); e_star text:=chr(10024); e_person text:=chr(128100); e_box text:=chr(128230); e_target text:=chr(127919); e_num text:=chr(128290); e_money text:=chr(128176); e_id text:=chr(127470); e_pin text:=chr(128204); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
  select coalesce(name,'Layanan') into v_service from public.services where id=new.service_id;
  perform public.wsid_notify_channel(
    '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
    ||'<blockquote><b>'||e_blue||' Order Baru</b>'||E'\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||e_person||' <i>User:</i> <b>'||replace(v_name,'&','&amp;')||'</b>'||E'\n'
    ||e_box||' <i>Layanan:</i> <b>'||replace(v_service,'&','&amp;')||'</b>'||E'\n'
    ||e_target||' <i>Target:</i> <code>'||replace(coalesce(new.target,'-'),'&','&amp;')||'</code>'||E'\n'
    ||e_num||' <i>Jumlah:</i> <b>'||new.quantity::text||'</b>'||E'\n'
    ||e_money||' <i>Total:</i> <b>'||public.wsid_rupiah(new.sale_total)||'</b>'||E'\n'
    ||e_id||' <i>ID:</i> <code>WSO-'||(upper(replace(new.id::text,'-','')))[1:10]||'</code>'||E'\n'
    ||e_pin||' <i>Status:</i> <b>'||coalesce(new.status,'pending')||'</b>'||E'\n'
    ||e_clock||' <i>Waktu:</i> <b>'||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB</b>'||E'\n\n'
    ||'━━━━━━━━━━━━━━━━━━'||E'\n'
    ||e_black||' <b>Witama Store. ID</b></blockquote>'
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_order_telegram on public.orders;
create trigger trg_wsid_order_telegram after insert on public.orders for each row execute function public.wsid_notify_order();

-- STATUS ORDER
create or replace function public.wsid_notify_order_status()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text; v_service text;
  e_box text:=chr(128230); e_star text:=chr(10024); e_person text:=chr(128100); e_id text:=chr(127470); e_pin text:=chr(128204); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  if old.status is distinct from new.status then
    select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
    select coalesce(name,'Layanan') into v_service from public.services where id=new.service_id;
    perform public.wsid_notify_channel(
      '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
      ||'<blockquote><b>'||e_box||' Order • Status Update</b>'||E'\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_person||' <i>User:</i> <b>'||replace(v_name,'&','&amp;')||'</b>'||E'\n'
      ||e_box||' <i>Layanan:</i> <b>'||replace(v_service,'&','&amp;')||'</b>'||E'\n'
      ||e_id||' <i>ID:</i> <code>WSO-'||(upper(replace(new.id::text,'-','')))[1:10]||'</code>'||E'\n'
      ||e_pin||' <i>Status:</i> <b>'||coalesce(new.status,'-')||'</b>'||E'\n'
      ||e_clock||' <i>Waktu:</i> <b>'||to_char(now() at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB</b>'||E'\n\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_black||' <b>Witama Store. ID</b></blockquote>'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_order_status_telegram on public.orders;
create trigger trg_wsid_order_status_telegram after update of status on public.orders for each row execute function public.wsid_notify_order_status();

-- PERUBAHAN SALDO
create or replace function public.wsid_notify_balance_transaction()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_name text; v_balance numeric;
  e_money text:=chr(128176); e_star text:=chr(10024); e_person text:=chr(128100); e_note text:=chr(128221); e_wallet text:=chr(128179); e_clock text:=chr(128336); e_black text:=chr(128420);
begin
  select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
  select balance into v_balance from public.wallets where user_id=new.user_id;
  if new.type in ('admin_credit','admin_debit','deposit','order') then
    perform public.wsid_notify_channel(
      '<b>Ws.ID | ALL MONITORING '||e_star||'</b>'||E'\n\n'
      ||'<blockquote><b>'||e_money||' Perubahan Saldo</b>'||E'\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_person||' <i>User:</i> <b>'||replace(v_name,'&','&amp;')||'</b>'||E'\n'
      ||e_money||' <i>Perubahan:</i> <b>'||case when new.amount>=0 then '+' else '' end||public.wsid_rupiah(new.amount)||'</b>'||E'\n'
      ||e_note||' <i>Keterangan:</i> <i>'||replace(coalesce(new.description,'-'),'&','&amp;')||'</i>'||E'\n'
      ||e_wallet||' <i>Saldo sekarang:</i> <b>'||public.wsid_rupiah(coalesce(v_balance,0))||'</b>'||E'\n'
      ||e_clock||' <i>Waktu:</i> <b>'||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB</b>'||E'\n\n'
      ||'━━━━━━━━━━━━━━━━━━'||E'\n'
      ||e_black||' <b>Witama Store. ID</b></blockquote>'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_transaction_telegram on public.transactions;
create trigger trg_wsid_transaction_telegram after insert on public.transactions for each row execute function public.wsid_notify_balance_transaction();

notify pgrst,'reload schema';
notify pgrst,'reload config';
