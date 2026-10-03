-- WSID SMM PANEL V30 - DUAL TELEGRAM + QUOTE FORMAT
-- Basis: V28 dual Telegram. This patch preserves the previous dual-send behavior.
-- It replaces ONLY the Telegram notification functions/triggers.
-- Safe to run after V28. Do NOT run old V29 formatting SQL afterward.

-- 1) Remove Telegram/HTTP notification triggers that could duplicate or conflict.
do $drop$
declare r record;
begin
  for r in
    select t.tgname, c.relname, p.proname
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    join pg_proc p on p.oid=t.tgfoid
    where not t.tgisinternal
      and n.nspname='public'
      and c.relname in ('deposits','orders','transactions','wallets')
      and (p.prosrc ilike '%telegram%'
        or p.prosrc ilike '%http%'
        or p.proname ilike '%telegram%'
        or p.proname ilike '%notif%')
  loop
    execute format('drop trigger if exists %I on public.%I', r.tgname, r.relname);
  end loop;
end
$drop$;

-- 2) HTML escape helper.
create or replace function public.wsid_html_escape(v text)
returns text
language sql
immutable
as $fn$
  select replace(replace(replace(coalesce(v,''),'&','&amp;'),'<','&lt;'),'>','&gt;');
$fn$;

-- 3) Telegram sender.
-- One call = one chat_id. Admin and group are ALWAYS sent with separate calls.
-- The message is HTML formatted and includes the website button when configured.
create or replace function public.wsid_send_telegram(
  v_token text,
  v_chat text,
  v_text text,
  v_url text default null
)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_body text;
begin
  if coalesce(trim(v_token),'')='' or coalesce(trim(v_chat),'')='' then
    return false;
  end if;

  begin
    v_body := 'chat_id='||extensions.urlencode(trim(v_chat))
           ||'&text='||extensions.urlencode(v_text)
           ||'&parse_mode=HTML';

    if coalesce(trim(v_url),'') ~* '^https?://' then
      v_body := v_body
             ||'&reply_markup='
             ||extensions.urlencode(
               jsonb_build_object(
                 'inline_keyboard',
                 jsonb_build_array(
                   jsonb_build_array(
                     jsonb_build_object(
                       'text','🌐 Buka Website WSID',
                       'url',trim(v_url)
                     )
                   )
                 )
               )::text
             );
    end if;

    perform extensions.http_post(
      'https://api.telegram.org/bot'||v_token||'/sendMessage',
      v_body,
      'application/x-www-form-urlencoded'
    );
    return true;
  exception when others then
    raise warning 'Telegram gagal ke %: %', v_chat, sqlerrm;
    return false;
  end;
end;
$fn$;

grant execute on function public.wsid_send_telegram(text,text,text,text) to authenticated;

-- Backward-compatible 3-argument helper.
create or replace function public.wsid_send_telegram(v_token text, v_chat text, v_text text)
returns boolean
language sql
security definer
set search_path = public, extensions
as $fn$
  select public.wsid_send_telegram(v_token, v_chat, v_text, null);
$fn$;

grant execute on function public.wsid_send_telegram(text,text,text) to authenticated;

-- 4) Automatic deposit/order notification.
-- EVERY message body is wrapped in a Telegram blockquote.
-- The same message is sent to BOTH admin and group.
create or replace function public.wsid_safe_notify()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_token text;
  v_admin text;
  v_group text;
  v_text text;
  v_url text;
  v_panel text;
  v_user_name text;
  v_user_email text;
  v_admin_ok boolean := false;
  v_group_ok boolean := false;
  v_when text := to_char(now() at time zone 'Asia/Jakarta','DD/MM/YYYY HH24:MI:SS');
  v_id text := coalesce(new.id::text,'-');
  v_method text;
  v_amount text;
  v_fee text;
  v_total text;
begin
  begin
    select bot_token, chat_id into v_token, v_admin
    from public.telegram_config where id=1;

    select value into v_group
    from public.panel_settings where key='telegram_notify_chat_id';

    select coalesce(value,'') into v_url
    from public.panel_settings where key='monitoring_website_url';

    select coalesce(value,'WSID SMM PANEL') into v_panel
    from public.panel_settings where key='panel_name';

    if tg_table_name='deposits' then
      select coalesce(full_name,''), coalesce(email,'')
      into v_user_name, v_user_email
      from public.profiles where id=new.user_id;

      v_amount := replace(to_char(coalesce(new.amount,0),'FM999999999999990.00'),'.',',');
      v_fee := replace(to_char(coalesce(new.fee_amount,0),'FM999999999999990.00'),'.',',');
      v_total := replace(to_char(coalesce(new.payment_total,0),'FM999999999999990.00'),'.',',');
      v_method := upper(coalesce(nullif(trim(new.payment_method),''),'-'));

      v_text := '<blockquote>'
             ||'🔔 <b>DEPOSIT BARU MENUNGGU ACC</b>'||E'\n'
             ||'━━━━━━━━━━━━━━━━━━'||E'\n'
             ||'👤 <b>User:</b> '||public.wsid_html_escape(coalesce(nullif(v_user_name,''),nullif(v_user_email,''),'User'))||E'\n'
             ||'💰 <b>Nominal:</b> Rp'||v_amount||E'\n'
             ||'💳 <b>Biaya Admin:</b> Rp'||v_fee||E'\n'
             ||'💵 <b>Total Transfer:</b> Rp'||v_total||E'\n'
             ||'🏦 <b>Metode:</b> '||public.wsid_html_escape(v_method)||E'\n'
             ||'🕒 <b>Waktu:</b> '||v_when||' WIB'||E'\n'
             ||'🆔 <b>ID:</b> <code>'||public.wsid_html_escape(v_id)||'</code>'||E'\n'
             ||'━━━━━━━━━━━━━━━━━━'||E'\n'
             ||'🖤 <b>'||public.wsid_html_escape(coalesce(v_panel,'WSID SMM PANEL'))||'</b>'
             ||'</blockquote>';
    else
      select coalesce(full_name,''), coalesce(email,'')
      into v_user_name, v_user_email
      from public.profiles where id=new.user_id;

      v_total := replace(to_char(coalesce(new.sale_total,0),'FM999999999999990.00'),'.',',');
      v_text := '<blockquote>'
             ||'🛒 <b>ORDER BARU MASUK</b>'||E'\n'
             ||'━━━━━━━━━━━━━━━━━━'||E'\n'
             ||'👤 <b>User:</b> '||public.wsid_html_escape(coalesce(nullif(v_user_name,''),nullif(v_user_email,''),'User'))||E'\n'
             ||'🎯 <b>Target:</b> [DISENSOR]'||E'\n'
             ||'📦 <b>Jumlah:</b> '||coalesce(new.quantity,0)::text||E'\n'
             ||'💵 <b>Total:</b> Rp'||v_total||E'\n'
             ||'🕒 <b>Waktu:</b> '||v_when||' WIB'||E'\n'
             ||'🆔 <b>ID:</b> <code>'||public.wsid_html_escape(v_id)||'</code>'||E'\n'
             ||'━━━━━━━━━━━━━━━━━━'||E'\n'
             ||'🖤 <b>'||public.wsid_html_escape(coalesce(v_panel,'WSID SMM PANEL'))||'</b>'
             ||'</blockquote>';
    end if;

    -- DO NOT replace these with coalesce/admin-only logic.
    -- They are intentionally two independent destinations.
    v_admin_ok := public.wsid_send_telegram(v_token, v_admin, v_text, v_url);
    v_group_ok := public.wsid_send_telegram(v_token, v_group, v_text, v_url);

    if not v_admin_ok and not v_group_ok then
      raise warning 'Notifikasi Telegram gagal ke Admin dan Grup.';
    end if;
  exception when others then
    raise warning 'Notifikasi Telegram gagal: %', sqlerrm;
  end;
  return new;
end;
$fn$;

drop trigger if exists wsid_notify_deposit on public.deposits;
create trigger wsid_notify_deposit after insert on public.deposits
for each row execute function public.wsid_safe_notify();

drop trigger if exists wsid_notify_order on public.orders;
create trigger wsid_notify_order after insert on public.orders
for each row execute function public.wsid_safe_notify();

-- 5) Test Telegram: two independent sends, Admin + Group.
create or replace function public.test_telegram_deposit_notification()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_token text;
  v_admin text;
  v_group text;
  v_admin_ok boolean := false;
  v_group_ok boolean := false;
  v_url text;
  v_msg text := '<blockquote>🔔 <b>TES NOTIFIKASI WSID SMM PANEL</b>'||E'\n'
             ||'━━━━━━━━━━━━━━━━━━'||E'\n'
             ||'🖤 <b>Notifikasi Telegram aktif</b></blockquote>';
begin
  if not public.is_admin() then
    return jsonb_build_object('status',false,'msg','Khusus admin');
  end if;

  select bot_token, chat_id into v_token, v_admin
  from public.telegram_config where id=1;

  select value into v_group
  from public.panel_settings where key='telegram_notify_chat_id';

  select value into v_url
  from public.panel_settings where key='monitoring_website_url';

  if coalesce(trim(v_token),'')='' then
    return jsonb_build_object('status',false,'msg','Token Bot Telegram belum diisi');
  end if;

  v_admin_ok := public.wsid_send_telegram(v_token, v_admin, v_msg, v_url);
  v_group_ok := public.wsid_send_telegram(v_token, v_group, v_msg, v_url);

  return jsonb_build_object(
    'status',(v_admin_ok or v_group_ok),
    'admin_sent',v_admin_ok,
    'group_sent',v_group_ok,
    'admin_chat',v_admin,
    'group_chat',v_group,
    'msg',case
      when v_admin_ok and v_group_ok then 'Tes berhasil dikirim ke Admin/Pribadi dan Grup/Channel.'
      when v_admin_ok then 'Tes berhasil ke Admin/Pribadi, tetapi gagal ke Grup/Channel.'
      when v_group_ok then 'Tes berhasil ke Grup/Channel, tetapi gagal ke Admin/Pribadi.'
      else 'Tes gagal ke kedua tujuan. Periksa ID chat, token, dan izin bot di grup.'
    end
  );
end;
$fn$;

grant execute on function public.test_telegram_deposit_notification() to authenticated;

notify pgrst, 'reload schema';
