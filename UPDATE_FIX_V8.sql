-- WSID SMM PANEL V8 HOTFIX
-- Jalankan SEKALI setelah RUN_ALL.sql + RUN_TANPA_EDGE.sql.
-- Tidak memakai Edge Function.

create extension if not exists pg_net with schema extensions;

-- =============================================================
-- QRIS: bucket publik untuk foto QRIS yang di-upload dari Admin.
-- =============================================================
insert into storage.buckets (id,name,public)
values ('panel-assets','panel-assets',true)
on conflict (id) do update set public=true;

drop policy if exists panel_assets_admin_insert on storage.objects;
create policy panel_assets_admin_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='panel-assets' and public.is_admin()
);

drop policy if exists panel_assets_admin_update on storage.objects;
create policy panel_assets_admin_update on storage.objects
for update to authenticated
using (bucket_id='panel-assets' and public.is_admin())
with check (bucket_id='panel-assets' and public.is_admin());

drop policy if exists panel_assets_admin_delete on storage.objects;
create policy panel_assets_admin_delete on storage.objects
for delete to authenticated
using (bucket_id='panel-assets' and public.is_admin());

-- =============================================================
-- Telegram SQL-only notification.
-- Perbaikan penting: gunakan schema tempat pg_net benar-benar
-- terpasang (extensions atau net), bukan memaksa net.
-- =============================================================
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
  select decrypted_secret into v_token
  from vault.decrypted_secrets
  where name='TOKEN_BOT_TELEGRAM'
  limit 1;

  if coalesce(v_token,'')='' then
    raise exception 'Secret TOKEN_BOT_TELEGRAM belum ditemukan di Vault';
  end if;
  if coalesce(trim(p_chat),'')='' then
    raise exception 'Telegram Chat ID belum diisi';
  end if;

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
      jsonb_build_object('chat_id',trim(p_chat),'text',p_text,'disable_web_page_preview',true),
      jsonb_build_object('Content-Type','application/json');

  return v_request;
end;
$$;

revoke all on function public.wsid_queue_telegram(text,text) from public;
grant execute on function public.wsid_queue_telegram(text,text) to authenticated;

create or replace function public.wsid_send_deposit_telegram()
returns trigger
language plpgsql
security definer
set search_path=public,extensions,vault
as $$
declare
  v_chat text;
  v_name text;
  v_email text;
  v_money text;
  v_created text;
  v_request bigint;
begin
  if new.status <> 'pending' then return new; end if;

  select trim(coalesce(value,'')) into v_chat
  from public.panel_settings
  where key='telegram_chat_id'
  limit 1;

  if coalesce(v_chat,'')='' then return new; end if;

  select coalesce(full_name,'User'),coalesce(email,'-')
    into v_name,v_email
  from public.profiles
  where id=new.user_id;

  v_money:='Rp '||to_char(new.amount,'FM999G999G999G999G990');
  v_created:=to_char(new.created_at at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI');

  begin
    v_request:=public.wsid_queue_telegram(
      v_chat,
      E'🔔 DEPOSIT BARU\n\n'
      ||'👤 User: '||coalesce(v_name,'User')||E'\n'
      ||'📧 Email: '||coalesce(v_email,'-')||E'\n'
      ||'💰 Nominal: '||v_money||E'\n'
      ||'🆔 ID: DEP-'||upper(replace(new.id::text,'-',''))||E'\n'
      ||'📌 Status: Menunggu ACC Admin\n'
      ||'🕐 '||v_created||' WIB'
    );
    raise log 'WSID Telegram deposit queued request id=%',v_request;
  exception when others then
    raise warning 'WSID Telegram deposit notification gagal: %',sqlerrm;
  end;

  return new;
end;
$$;

drop trigger if exists trg_wsid_deposit_telegram on public.deposits;
create trigger trg_wsid_deposit_telegram
after insert on public.deposits
for each row execute function public.wsid_send_deposit_telegram();

-- Tombol Tes Telegram dari Admin Panel.
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
    return jsonb_build_object('status',false,'msg','Akses admin ditolak.');
  end if;

  select trim(coalesce(value,'')) into v_chat
  from public.panel_settings where key='telegram_chat_id' limit 1;

  if coalesce(v_chat,'')='' then
    return jsonb_build_object('status',false,'msg','Telegram Chat ID belum diisi.');
  end if;

  begin
    v_req:=public.wsid_queue_telegram(
      v_chat,
      E'🔔 TEST WSID SMM PANEL\n\nNotifikasi Telegram berhasil terhubung.\nPesan deposit baru akan dikirim ke chat ini.'
    );
    return jsonb_build_object('status',true,'msg','Tes Telegram berhasil diantrikan. Request ID: '||v_req::text);
  exception when others then
    return jsonb_build_object('status',false,'msg',sqlerrm);
  end;
end;
$$;

grant execute on function public.test_telegram_deposit_notification() to authenticated;

notify pgrst,'reload schema';
notify pgrst,'reload config';
