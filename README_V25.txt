WSID SMM PANEL V25

PERBAIKAN SQL UTAMA
- Memperbaiki error: cannot subscript type text because it does not support subscripting.
- Memperbaiki konflik policy: deposit_proofs_insert_v24 already exists.
- Policy V24 lama dibersihkan sebelum dibuat ulang.
- SQL aman dijalankan ulang jika sebelumnya berhenti di tengah.
- Tidak menghapus data user, saldo, order, atau deposit lama.

CARA PAKAI
1. Buka Supabase > SQL Editor.
2. Buka file UPDATE_FIX_V25.sql.
3. Salin seluruh isinya ke query baru.
4. Tekan Run.
5. Pastikan hasilnya Success.
6. Setelah itu refresh website dan coba pilih bukti transfer lagi.

PENTING
Jangan jalankan FINAL_V22.sql lagi. Gunakan patch V25 ini untuk database yang sudah ada.

LOGO PEMBAYARAN
Di Admin > Settings, scroll ke bagian Logo Pembayaran. Admin dapat mengunggah logo DANA, GoPay, dan QRIS dari HP.
