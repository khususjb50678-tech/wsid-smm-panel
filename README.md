WSID SMM PANEL — V8

Perubahan utama:
- Buy button + aturan order bernomor setelah Buy
- QRIS upload dari Admin > Settings
- Bukti transfer diperbaiki + nama file tampil
- Menu Pesanan -> Riwayat
- ID riwayat user dan pencarian ID di Admin
- Telegram deposit SQL-only diperbaiki dengan pg_net
- Tombol Tes Telegram di Admin > Settings

SETELAH ZIP DIUPLOAD KE ROOT GITHUB:
1. Jalankan UPDATE_FIX_V8.sql satu kali di Supabase SQL Editor.
2. Di Admin > Settings, isi Telegram Chat ID.
3. Tekan Tes Telegram.
4. Upload QRIS dari Settings bila diperlukan.

BOT TOKEN tetap berada di Supabase Vault. Jangan masukkan ke GitHub.
