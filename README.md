# WSID SMM PANEL

Website mobile/portrait untuk panel layanan sosial media dengan GitHub Pages + Supabase.

## Fitur final
- Login & register
- Dashboard mobile/portrait
- Order dan riwayat pesanan
- Deposit manual DANA
- Nominal deposit diketik sendiri
- Minimum deposit Rp2.000
- Upload bukti pembayaran
- Status deposit: Menunggu ACC Admin
- Admin ACC/Tolak deposit
- Notifikasi deposit di Admin Panel
- Notifikasi deposit ke Telegram Bot
- Branding, DANA, QRIS, kontak, dan Chat ID Telegram dikelola dari Admin > Settings
- Koneksi layanan dan markup dikelola dari Admin > Koneksi
- Deskripsi layanan dibersihkan dari HTML mentah

## Yang sengaja belum dipakai
- Docs API publik
- API ID/API Key untuk user

## Telegram
Bot token Telegram **tidak** disimpan di GitHub atau frontend. Simpan sebagai Supabase Edge Function Secret dengan nama:

`TELEGRAM_BOT_TOKEN`

Chat ID admin diisi dari **Admin > Settings > Notifikasi Telegram**.

Deploy Edge Function `telegram-deposit-notify` dari file `SQL Telegram notification`.

## Supabase
Jalankan `RUN_ALL.sql` sekali di Supabase SQL Editor. File tersebut membuat tabel, RLS, bucket bukti deposit, validasi minimum Rp2.000, dan fungsi database yang diperlukan.

## GitHub Pages
Upload semua file ZIP langsung ke ROOT repository.
