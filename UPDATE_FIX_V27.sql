-- ============================================================
-- WSID SMM PANEL V27 - FIX TRIGGER NOTIFIKASI (penyebab error deposit & order)
-- Aman dijalankan ulang. Tidak menghapus data user/saldo/order/deposit.
-- Jalankan SETELAH UPDATE_FIX_V26.sql.
-- ============================================================

-- 1) Hapus trigger lama di tabel deposits/orders/transactions/wallets
--    yang fungsinya memakai Telegram/HTTP/subscript (sumber error "cannot subscript type text").
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
      and ( p.prosrc ilike '%telegram%'
         or p.prosrc ilike '%http%'
         or p.prosrc ~* '\)\s*\[[0-9a-z_'']+\]'
         or p.proname ilike '%telegram%'
         or p.proname ilike '%notif%' )
  loop
    execute format('drop trigger if exists %I on public.%I', r.tgname, r.relname);
    raise notice 'Trigger dihapus: % di % (fungsi %)', r.tgname, r.relname, r.proname;
  end loop;
end
$drop$;

-- 2) Notifikasi Telegram versi AMAN: tanpa subscript, dan error apa pun TIDAK membatalkan deposit/order.
create or replace function public.wsid_safe_notify()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare
  v_token text;
  v_chat text;
  v_notify text;
  v_text text;
begin
  begin
    select bot_token, chat_id into v_token, v_chat from public.telegram_config where id=1;
    select value into v_notify from public.panel_settings where key='telegram_notify_chat_id';
    v_chat := coalesce(nullif(trim(coalesce(v_notify,'')),''), v_chat);

    if coalesce(v_token,'')='' or coalesce(v_chat,'')='' then
      return new;
    end if;

    if tg_table_name='deposits' then
      v_text := 'Deposit baru menunggu ACC. Nominal: Rp'||coalesce(new.amount,0)::text
                ||' | Total transfer: Rp'||coalesce(new.payment_total,0)::text
                ||' | Metode: '||coalesce(new.payment_method,'-');
    else
      v_text := 'Order baru masuk. Target: '||coalesce(new.target,'-')
                ||' | Qty: '||coalesce(new.quantity,0)::text
                ||' | Total: Rp'||coalesce(new.sale_total,0)::text;
    end if;

    perform extensions.http_post(
      'https://api.telegram.org/bot'||v_token||'/sendMessage',
      'chat_id='||extensions.urlencode(v_chat)||'&text='||extensions.urlencode(v_text),
      'application/x-www-form-urlencoded'
    );
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

-- 3) Tes Telegram admin versi aman (tidak error walau token kosong).
create or replace function public.test_telegram_deposit_notification()
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $fn$
declare v_token text; v_chat text;
begin
  if not public.is_admin() then return jsonb_build_object('status',false,'msg','Khusus admin'); end if;
  select bot_token, chat_id into v_token, v_chat from public.telegram_config where id=1;
  if coalesce(v_token,'')='' or coalesce(v_chat,'')='' then
    return jsonb_build_object('status',false,'msg','Token / ID Telegram belum diisi');
  end if;
  begin
    perform extensions.http_post(
      'https://api.telegram.org/bot'||v_token||'/sendMessage',
      'chat_id='||extensions.urlencode(v_chat)||'&text='||extensions.urlencode('Tes notifikasi WSID SMM PANEL berhasil'),
      'application/x-www-form-urlencoded');
  exception when others then
    return jsonb_build_object('status',false,'msg','Gagal: '||sqlerrm);
  end;
  return jsonb_build_object('status',true,'msg','Notifikasi Telegram dikirim.');
end;
$fn$;
grant execute on function public.test_telegram_deposit_notification() to authenticated;

notify pgrst, 'reload schema';

-- 4) DIAGNOSTIK: daftar trigger yang aktif sekarang (kirim hasilnya jika masih error).
select c.relname as tabel, t.tgname as trigger, p.proname as fungsi
from pg_trigger t
join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
join pg_proc p on p.oid=t.tgfoid
where not t.tgisinternal and n.nspname='public'
order by 1,2;
