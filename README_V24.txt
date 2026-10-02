WSID SMM PANEL V24

Perbaikan utama:
- Memperbaiki error PostgreSQL "cannot subscript type text because it does not support subscripting" pada upload bukti deposit.
- Memperbaiki RPC request_deposit.
- Memperbaiki RPC create_order dan submit_order.
- Menambahkan pengaturan upload logo DANA, GoPay, dan QRIS dari Admin > Settings.
- Logo pembayaran di halaman Deposit hanya menampilkan gambar/logo yang diatur Admin.

PENTING:
1. File website di ZIP ini menggantikan file lama di GitHub.
2. Setelah upload file website, jalankan FIX_V24.sql SATU KALI di Supabase SQL Editor.
3. Jangan jalankan SQL versi lama FINAL_V22.sql lagi.
4. Setelah SQL sukses, refresh website dengan cache baru.
5. Admin > Settings > Logo Pembayaran digunakan untuk upload logo DANA, GoPay, dan QRIS.
