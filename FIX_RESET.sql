-- WSID SMM PANEL - FIX RESET
-- Jalankan file ini SAJA untuk memperbaiki fitur Reset.
-- Tidak menghapus akun/profiles user.

create or replace function public.admin_reset_panel_data(p_target text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $reset$
declare
  v_target text := lower(trim(coalesce(p_target, '')));
  v_count bigint := 0;
begin
  if not public.is_admin() then
    raise exception 'Akses ditolak';
  end if;

  if v_target = 'profit' then
    update public.orders
       set profit = 0,
           updated_at = now()
     where id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua profit order berhasil direset menjadi Rp0.'
    );

  elsif v_target = 'balance' then
    update public.wallets
       set balance = 0,
           updated_at = now()
     where user_id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua saldo user berhasil direset menjadi Rp0.'
    );

  elsif v_target = 'orders' then
    delete from public.orders
     where id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua riwayat order berhasil dihapus.'
    );

  elsif v_target = 'deposits' then
    delete from public.deposits
     where id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua riwayat deposit berhasil dihapus.'
    );

  elsif v_target = 'transactions' then
    delete from public.transactions
     where id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua transaksi berhasil dihapus.'
    );

  elsif v_target = 'logins' then
    delete from public.login_events
     where id is not null;
    get diagnostics v_count = row_count;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'count', v_count,
      'message', 'Semua aktivitas login berhasil dihapus.'
    );

  elsif v_target = 'all_activity' then
    delete from public.transactions
     where id is not null;
    delete from public.deposits
     where id is not null;
    delete from public.orders
     where id is not null;
    delete from public.login_events
     where id is not null;
    update public.wallets
       set balance = 0,
           updated_at = now()
     where user_id is not null;
    return jsonb_build_object(
      'status', true,
      'target', v_target,
      'message', 'Semua data aktivitas, saldo, order, deposit, transaksi dan login berhasil direset. Akun user tetap ada.'
    );

  else
    raise exception 'Target reset tidak dikenal: %. Gunakan profit, balance, orders, deposits, transactions, logins, atau all_activity.', v_target;
  end if;
end;
$reset$;

grant execute on function public.admin_reset_panel_data(text) to authenticated;

notify pgrst, 'reload schema';
