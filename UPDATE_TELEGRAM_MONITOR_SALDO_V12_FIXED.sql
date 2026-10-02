-- WSID SMM PANEL V12 - SQL ONLY (TANPA EDGE FUNCTION)
-- Fitur:
-- 1. Tambah/kurangi saldo user dari Admin Panel
-- 2. Pantau semua user + saldo + login terakhir
-- 3. Catat login user
-- 4. Notifikasi Telegram untuk login, user baru, deposit, order, perubahan status order, dan perubahan saldo
-- 5. Link bot Telegram dapat diatur dari Admin Settings

create table if not exists public.login_events(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  email text,
  full_name text,
  created_at timestamptz default now()
);

alter table public.login_events enable row level security;
drop policy if exists login_events_insert_self on public.login_events;
create policy login_events_insert_self on public.login_events
for insert to authenticated
with check (user_id=auth.uid());
drop policy if exists login_events_admin_read on public.login_events;
create policy login_events_admin_read on public.login_events
for select to authenticated
using (public.is_admin());

grant select,insert on public.login_events to authenticated;

-- Add a configurable Telegram bot username so notifications can contain a clickable link.
insert into public.panel_settings(key,value)
values ('telegram_bot_username','')
on conflict (key) do nothing;

-- Admin-only balance adjustment. Positive = tambah, negative = kurangi.
create or replace function public.admin_adjust_balance(
  p_user_id uuid,
  p_amount numeric,
  p_description text default null
) returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare
  v_balance numeric;
  v_desc text;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;
  if p_user_id is null then raise exception 'User tidak ditemukan'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'Nominal harus lebih dari 0'; end if;

  insert into public.wallets(user_id,balance)
  values(p_user_id,0)
  on conflict (user_id) do nothing;

  select balance into v_balance
  from public.wallets
  where user_id=p_user_id
  for update;

  if v_balance + p_amount < 0 then
    raise exception 'Saldo tidak cukup untuk dikurangi';
  end if;

  update public.wallets
  set balance=balance+p_amount,updated_at=now()
  where user_id=p_user_id
  returning balance into v_balance;

  v_desc:=coalesce(nullif(trim(p_description),''),case when p_amount>0 then 'Admin tambah saldo' else 'Admin kurangi saldo' end);
  insert into public.transactions(user_id,type,amount,description)
  values(p_user_id,case when p_amount>0 then 'admin_credit' else 'admin_debit' end,p_amount,v_desc);

  return v_balance;
end;
$$;

grant execute on function public.admin_adjust_balance(uuid,numeric,text) to authenticated;

-- Make the Telegram queue accept HTML formatting and clickable links.
create or replace function public.wsid_queue_telegram(p_chat text,p_text text)
returns bigint
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_token text;
  v_request bigint;
  v_fn text;
  v_url text;
begin
  select nullif(trim(bot_token),'') into v_token
  from public.telegram_config where id=1 limit 1;
  if coalesce(v_token,'')='' then
    begin
      select decrypted_secret into v_token from vault.decrypted_secrets where name='TOKEN_BOT_TELEGRAM' limit 1;
    exception when others then v_token:=null; end;
  end if;
  if coalesce(v_token,'')='' then raise exception 'Token Bot Telegram belum diisi.'; end if;
  if coalesce(trim(p_chat),'')='' then raise exception 'ID Telegram belum diisi.'; end if;
  v_url:='https://api.telegram.org/bot'||v_token||'/sendMessage';
  if to_regprocedure('extensions.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
    v_fn:='extensions.http_post';
  elsif to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
    v_fn:='net.http_post';
  else
    raise exception 'pg_net belum tersedia. Aktifkan extension pg_net di Supabase.';
  end if;
  execute format('select %s($1,$2,''{}''::jsonb,$3,5000)',v_fn)
    into v_request
    using v_url,
      jsonb_build_object('chat_id',trim(p_chat),'text',p_text,'parse_mode','HTML','disable_web_page_preview',false),
      jsonb_build_object('Content-Type','application/json');
  return v_request;
end;
$$;

-- Central helper for channel/chat notifications.
create or replace function public.wsid_notify_channel(p_text text)
returns void
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_req bigint;
begin
  select nullif(trim(chat_id),'') into v_chat from public.telegram_config where id=1 limit 1;
  if coalesce(v_chat,'')='' then
    select nullif(trim(value),'') into v_chat from public.panel_settings where key='telegram_chat_id' limit 1;
  end if;
  if coalesce(v_chat,'')='' then return; end if;
  begin
    v_req:=public.wsid_queue_telegram(v_chat,p_text);
  exception when others then
    raise warning 'WSID Telegram notification gagal: %',sqlerrm;
  end;
end;
$$;

-- New user registration notification.
create or replace function public.wsid_notify_new_user()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_bot text; v_link text;
begin
  select nullif(trim(value),'') into v_bot from public.panel_settings where key='telegram_bot_username' limit 1;
  v_link:=case when coalesce(v_bot,'')<>'' then E'\n🔗 <a href="https://t.me/'||replace(v_bot,'@','')||'">Buka Bot WSID</a>' else '' end;
  perform public.wsid_notify_channel(
    E'✨ <b>USER BARU TERDAFTAR</b> ✨\n\n'
    ||'👤 <b>Nama:</b> '||coalesce(new.full_name,'Member')||E'\n'
    ||'📧 <b>Email:</b> '||coalesce(new.email,'-')||E'\n'
    ||'🆔 <b>User ID:</b> <code>'||new.id::text||E'</code>\n'
    ||'🕐 <b>Waktu:</b> '||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
    ||v_link
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_new_user_telegram on public.profiles;
create trigger trg_wsid_new_user_telegram after insert on public.profiles for each row execute function public.wsid_notify_new_user();

-- Login notification (inserted by the frontend after successful login).
create or replace function public.wsid_notify_login()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_bot text; v_link text;
begin
  select nullif(trim(value),'') into v_bot from public.panel_settings where key='telegram_bot_username' limit 1;
  v_link:=case when coalesce(v_bot,'')<>'' then E'\n🔗 <a href="https://t.me/'||replace(v_bot,'@','')||'">Buka Bot WSID</a>' else '' end;
  perform public.wsid_notify_channel(
    E'🟢 <b>USER LOGIN</b> 🟢\n\n'
    ||'👤 <b>Nama:</b> '||coalesce(new.full_name,'Member')||E'\n'
    ||'📧 <b>Email:</b> '||coalesce(new.email,'-')||E'\n'
    ||'🕐 <b>Waktu:</b> '||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI:SS')||' WIB'
    ||v_link
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_login_telegram on public.login_events;
create trigger trg_wsid_login_telegram after insert on public.login_events for each row execute function public.wsid_notify_login();

-- Deposit notification: replace old trigger with a richer message.
create or replace function public.wsid_send_deposit_telegram()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text; v_email text; v_money text;
begin
  if new.status <> 'pending' then return new; end if;
  select coalesce(full_name,'User'),coalesce(email,'-') into v_name,v_email from public.profiles where id=new.user_id;
  v_money:='Rp '||to_char(new.amount,'FM999G999G999G999G990');
  perform public.wsid_notify_channel(
    E'🔔 <b>DEPOSIT BARU</b> 🔔\n\n'
    ||'👤 <b>User:</b> '||v_name||E'\n'
    ||'📧 <b>Email:</b> '||v_email||E'\n'
    ||'💰 <b>Nominal:</b> '||v_money||E'\n'
    ||'🆔 <b>ID:</b> <code>DEP-'||upper(replace(new.id::text,'-',''))||E'</code>\n'
    ||'📌 <b>Status:</b> Menunggu ACC Admin\n'
    ||'🕐 <b>Waktu:</b> '||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_deposit_telegram on public.deposits;
create trigger trg_wsid_deposit_telegram after insert on public.deposits for each row execute function public.wsid_send_deposit_telegram();

-- Deposit status notification (approved/rejected). Avoid duplicate for initial insert.
create or replace function public.wsid_notify_deposit_status()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text; v_money text; v_status text;
begin
  if tg_op='UPDATE' and old.status is distinct from new.status then
    select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
    v_money:='Rp '||to_char(new.amount,'FM999G999G999G999G990');
    v_status:=case when new.status='approved' then '✅ Disetujui / ACC' when new.status='rejected' then '❌ Ditolak' else new.status end;
    perform public.wsid_notify_channel(
      E'💳 <b>STATUS DEPOSIT BERUBAH</b>\n\n'
      ||'👤 <b>User:</b> '||v_name||E'\n'
      ||'💰 <b>Nominal:</b> '||v_money||E'\n'
      ||'🆔 <b>ID:</b> <code>DEP-'||upper(replace(new.id::text,'-',''))||E'</code>\n'
      ||'📌 <b>Status:</b> '||v_status||E'\n'
      ||'🕐 <b>Waktu:</b> '||to_char(coalesce(new.reviewed_at,now()) at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_deposit_status_telegram on public.deposits;
create trigger trg_wsid_deposit_status_telegram after update of status on public.deposits for each row execute function public.wsid_notify_deposit_status();

-- Order notification on create.
create or replace function public.wsid_notify_order()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text; v_service text;
begin
  select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
  select coalesce(name,'Layanan') into v_service from public.services where id=new.service_id;
  perform public.wsid_notify_channel(
    E'🛒 <b>ORDER BARU</b> 🛒\n\n'
    ||'👤 <b>User:</b> '||v_name||E'\n'
    ||'📦 <b>Layanan:</b> '||v_service||E'\n'
    ||'🎯 <b>Target:</b> <code>'||coalesce(new.target,'-')||E'</code>\n'
    ||'🔢 <b>Jumlah:</b> '||new.quantity::text||E'\n'
    ||'💰 <b>Total:</b> Rp '||to_char(new.sale_total,'FM999G999G999G999G990')||E'\n'
    ||'🆔 <b>ID:</b> <code>WSO-'||(upper(replace(new.id::text,'-','')))[1:10]||E'</code>\n'
    ||'📌 <b>Status:</b> '||coalesce(new.status,'pending')||E'\n'
    ||'🕐 <b>Waktu:</b> '||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
  );
  return new;
end;
$$;
drop trigger if exists trg_wsid_order_telegram on public.orders;
create trigger trg_wsid_order_telegram after insert on public.orders for each row execute function public.wsid_notify_order();

-- Order status changes.
create or replace function public.wsid_notify_order_status()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text; v_service text;
begin
  if old.status is distinct from new.status then
    select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
    select coalesce(name,'Layanan') into v_service from public.services where id=new.service_id;
    perform public.wsid_notify_channel(
      E'📦 <b>STATUS ORDER BERUBAH</b>\n\n'
      ||'👤 <b>User:</b> '||v_name||E'\n'
      ||'📦 <b>Layanan:</b> '||v_service||E'\n'
      ||'🆔 <b>ID:</b> <code>WSO-'||(upper(replace(new.id::text,'-','')))[1:10]||E'</code>\n'
      ||'📌 <b>Status:</b> '||coalesce(new.status,'-')||E'\n'
      ||'🕐 <b>Waktu:</b> '||to_char(now() at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_order_status_telegram on public.orders;
create trigger trg_wsid_order_status_telegram after update of status on public.orders for each row execute function public.wsid_notify_order_status();

-- Balance changes, including admin add/reduce and order deductions.
create or replace function public.wsid_notify_balance_transaction()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text; v_balance numeric;
begin
  select coalesce(full_name,'User') into v_name from public.profiles where id=new.user_id;
  select balance into v_balance from public.wallets where user_id=new.user_id;
  if new.type in ('admin_credit','admin_debit','deposit','order') then
    perform public.wsid_notify_channel(
      E'💳 <b>PERUBAHAN SALDO</b>\n\n'
      ||'👤 <b>User:</b> '||v_name||E'\n'
      ||'💵 <b>Perubahan:</b> '||case when new.amount>=0 then '+' else '' end||'Rp '||to_char(new.amount,'FM999G999G999G999G990')||E'\n'
      ||'📝 <b>Keterangan:</b> '||coalesce(new.description,'-')||E'\n'
      ||'💰 <b>Saldo sekarang:</b> Rp '||to_char(coalesce(v_balance,0),'FM999G999G999G999G990')||E'\n'
      ||'🕐 <b>Waktu:</b> '||to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI')||' WIB'
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_wsid_transaction_telegram on public.transactions;
create trigger trg_wsid_transaction_telegram after insert on public.transactions for each row execute function public.wsid_notify_balance_transaction();

notify pgrst,'reload schema';
notify pgrst,'reload config';
