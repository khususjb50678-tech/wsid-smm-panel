-- WSID SMM PANEL V13
-- SQL ONLY. Tidak memakai Supabase Edge Function.
-- Tambahan:
-- 1) Channel/Grup Telegram khusus notifikasi
-- 2) Link bot otomatis pada notifikasi
-- 3) Reset terpisah: profit, saldo, order, deposit, transaksi, login, semua aktivitas
-- 4) Semua reset hanya bisa dijalankan oleh admin dan tidak menghapus akun user.

create table if not exists public.telegram_config(
  id integer primary key default 1 check(id=1),
  bot_token text,
  chat_id text,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz default now()
);

alter table public.telegram_config enable row level security;
drop policy if exists telegram_config_admin on public.telegram_config;
create policy telegram_config_admin on public.telegram_config
for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.telegram_config(id) values(1) on conflict(id) do nothing;

insert into public.panel_settings(key,value)
values ('telegram_notify_chat_id','')
on conflict(key) do nothing;

-- Helper tujuan notifikasi: field khusus Channel/Grup, lalu fallback ke ID Telegram lama.
create or replace function public.wsid_notify_channel(p_text text)
returns void
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_bot text;
  v_text text:=p_text;
  v_request bigint;
begin
  select nullif(trim(value),'') into v_chat
  from public.panel_settings
  where key='telegram_notify_chat_id'
  limit 1;

  if coalesce(v_chat,'')='' then
    select nullif(trim(chat_id),'') into v_chat
    from public.telegram_config
    where id=1
    limit 1;
  end if;

  if coalesce(v_chat,'')='' then
    select nullif(trim(value),'') into v_chat
    from public.panel_settings
    where key='telegram_chat_id'
    limit 1;
  end if;

  if coalesce(v_chat,'')='' then return; end if;

  -- Tambahkan link bot ke setiap notifikasi bila username bot sudah diatur.
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

-- Tes Telegram sekarang mengarah ke Channel/Grup Notifikasi jika diisi.
create or replace function public.test_telegram_deposit_notification()
returns jsonb
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_req bigint;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  select nullif(trim(value),'') into v_chat
  from public.panel_settings
  where key='telegram_notify_chat_id'
  limit 1;

  if coalesce(v_chat,'')='' then
    select nullif(trim(chat_id),'') into v_chat
    from public.telegram_config where id=1 limit 1;
  end if;

  if coalesce(v_chat,'')='' then
    return jsonb_build_object('status',false,'msg','Channel/Grup Notifikasi belum diisi.');
  end if;

  begin
    v_req:=public.wsid_queue_telegram(
      v_chat,
      E'🔔 <b>TEST WSID SMM PANEL</b> 🔔\n\nNotifikasi Channel/Grup berhasil terhubung.\nSemua user baru, login, deposit, order, perubahan status dan saldo akan dikirim ke sini.'
    );
    return jsonb_build_object('status',true,'msg','Tes Telegram berhasil diantrikan. Request ID: '||v_req::text);
  exception when others then
    return jsonb_build_object('status',false,'msg',sqlerrm);
  end;
end;
$$;

grant execute on function public.test_telegram_deposit_notification() to authenticated;

create table if not exists public.login_events(
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  email text,
  full_name text,
  created_at timestamptz default now()
);

alter table public.login_events enable row level security;
drop policy if exists login_events_insert_self on public.login_events;
create policy login_events_insert_self on public.login_events for insert to authenticated with check(user_id=auth.uid());
drop policy if exists login_events_admin_read on public.login_events;
create policy login_events_admin_read on public.login_events for select to authenticated using(public.is_admin());
grant select,insert on public.login_events to authenticated;

-- Reset terpisah. Akun user/profiles TIDAK dihapus.
create or replace function public.admin_reset_panel_data(p_target text)
returns jsonb
language plpgsql
security definer
set search_path=public,extensions
as $$
declare
  v_target text:=lower(trim(coalesce(p_target,'')));
  v_count bigint:=0;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  if v_target='profit' then
    update public.orders set profit=0,updated_at=now();
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua profit order berhasil direset menjadi Rp0.');

  elsif v_target='balance' then
    update public.wallets set balance=0,updated_at=now();
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua saldo user berhasil direset menjadi Rp0.');

  elsif v_target='orders' then
    delete from public.orders;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua riwayat order berhasil dihapus.');

  elsif v_target='deposits' then
    delete from public.deposits;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua riwayat deposit berhasil dihapus.');

  elsif v_target='transactions' then
    delete from public.transactions;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua transaksi berhasil dihapus.');

  elsif v_target='logins' then
    delete from public.login_events;
    get diagnostics v_count=row_count;
    return jsonb_build_object('status',true,'target',v_target,'count',v_count,'message','Semua aktivitas login berhasil dihapus.');

  elsif v_target='all_activity' then
    delete from public.transactions;
    delete from public.deposits;
    delete from public.orders;
    delete from public.login_events;
    update public.wallets set balance=0,updated_at=now();
    return jsonb_build_object('status',true,'target',v_target,'message','Semua data aktivitas, saldo, order, deposit, transaksi dan login berhasil direset. Akun user tetap ada.');

  else
    raise exception 'Target reset tidak dikenal: %. Gunakan profit, balance, orders, deposits, transactions, logins, atau all_activity.',v_target;
  end if;
end;
$$;

grant execute on function public.admin_reset_panel_data(text) to authenticated;

notify pgrst,'reload schema';
notify pgrst,'reload config';
