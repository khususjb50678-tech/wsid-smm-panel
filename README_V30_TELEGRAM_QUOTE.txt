WSID SMM PANEL V30 - DUAL TELEGRAM + QUOTE FORMAT

PERUBAHAN:
- Mempertahankan dual Telegram dari V28: setiap notifikasi dikirim ke Admin/Pribadi DAN Grup/Channel.
- Format deposit/order sekarang dibungkus Telegram <blockquote>.
- Tombol "Buka Website WSID" tetap dipertahankan bila monitoring_website_url diisi.
- Tes Telegram juga dikirim ke dua tujuan.
- Tidak mengubah data user, saldo, deposit, order, atau ID Telegram.

CARA PAKAI:
1. Pertahankan file frontend/admin.js dari V28 yang sekarang sudah berhasil dual Telegram.
2. Di Supabase SQL Editor, jalankan HANYA UPDATE_FIX_V30_TELEGRAM_QUOTE.sql.
3. Jangan jalankan SQL V29 setelah ini karena dapat menimpa format/fungsi.
4. Pastikan ID Admin/Test tetap di telegram_config.chat_id dan ID grup tetap di panel_settings key telegram_notify_chat_id.
5. Tes dengan membuat deposit baru.
