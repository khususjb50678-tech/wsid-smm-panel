WSID SMM PANEL V26

PERBAIKAN
- Penyebab error "cannot subscript type text..." : masih ada policy storage lama (nama berbeda) yang memakai (storage.foldername(name))[1]. Patch V25 hanya menghapus policy bernama tertentu.
- V26 menghapus otomatis SEMUA policy storage terkait deposit-proofs/foldername lalu membuat ulang versi aman (split_part).
- Policy bucket panel-assets (logo/QRIS) dibuat ulang aman.
- Fungsi request_deposit, create_order, submit_order disertakan ulang (aman dijalankan ulang).
- Frontend: pesan error sekarang lebih jelas dan tombol tidak bisa ditekan dua kali.

CARA PAKAI
1. Supabase > SQL Editor > New query.
2. Salin seluruh isi UPDATE_FIX_V26.sql lalu Run.
3. Hasil akhir (tabel diagnostik) harus KOSONG. Jika ada baris, kirim ke developer.
4. Upload file frontend (app.js) terbaru ke GitHub, hard refresh (clear cache).
5. Coba deposit & order lagi.
