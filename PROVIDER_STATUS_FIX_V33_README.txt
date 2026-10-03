WSID SMM PANEL V33 - FIX STATUS PROVIDER + DETAIL RIWAYAT

Yang diperbaiki
1) Detail riwayat tidak muncul saat diklik: atribut onclick memakai tanda kutip ganda
   di dalam atribut berkutip ganda sehingga JavaScript error. (app.js) Tombol "Refresh Status"
   dan tombol "Salin" nomor deposit punya bug yang sama, ikut diperbaiki.
2) Status order tidak mengikuti provider: SQL sinkron dibuat lebih kuat (UPDATE_FIX_V33_PROVIDER_STATUS.sql).
   Status: Completed/Success -> Sukses, Processing -> Diproses, Pending -> Menunggu,
   Partial -> Sebagian, Failed/Error/Cancel/Refund -> Gagal.
3) Halaman Riwayat tidak lagi menunggu sinkron provider sebelum tampil (sinkron di latar belakang).
4) Kalau provider gagal dibaca, pesan penyebabnya tampil merah di detail riwayat.

Cara pasang
1. Upload app.js baru ke GitHub/Vercel (deploy ulang).
2. Supabase > SQL Editor > jalankan UPDATE_FIX_V33_PROVIDER_STATUS.sql SEKALI.
3. Buka Riwayat, tunggu sampai 20 detik, atau tap order > Refresh Status.
