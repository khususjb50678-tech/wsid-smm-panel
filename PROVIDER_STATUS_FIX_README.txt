WSID SMM PANEL - PROVIDER STATUS FIX

Masalah yang diperbaiki:
Provider sudah Completed tetapi riwayat WSID masih Diproses.

Perubahan:
- Panel sekarang mengecek status provider saat halaman Riwayat dibuka.
- Selama halaman Riwayat terbuka, pengecekan otomatis dilakukan setiap 20 detik.
- Completed / Success -> Sukses
- Processing / In Progress -> Diproses
- Pending -> Menunggu
- Partial -> Sebagian
- Failed / Error / Canceled / Cancelled -> Gagal
- Status provider yang tidak dikenal TIDAK dipaksa menjadi gagal.
- Provider order ID memakai kolom provider_order_id bila tersedia; jika tidak, memakai ID order panel.

CARA PASANG:
1. Deploy file frontend dari ZIP ini ke GitHub/Vercel.
2. Supabase > SQL Editor.
3. Jalankan UPDATE_FIX_V32_PROVIDER_STATUS.sql SEKALI.
4. Buka Riwayat di panel dan tunggu maksimal 20 detik.

Catatan:
- Patch ini hanya menyentuh sinkronisasi status order.
- Tidak mengubah pembuatan order, harga, saldo, deposit, Telegram, target privacy,
  berita, syarat & ketentuan, penjelasan status, login/register, atau Safe Browser.
- Jika extension "http" belum aktif di Supabase, aktifkan extension http karena patch
  memakai extensions.http_post untuk membaca status provider secara server-side.
