const C=window.WSID_CONFIG||{};
const money=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(n||0));
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let tab='dashboard',lastPendingDeposits=null,depositPoll=null;

async function init(){
  if(!sb)return out('Koneksi Supabase belum siap.');
  const q=await sb.auth.getSession();
  if(!q.data.session)return location.href='login.html';
  const p=await sb.from('profiles').select('*').eq('id',q.data.session.user.id).single();
  if(p.data?.role!=='admin')return out('Akses admin ditolak.');
  draw();
  startDepositNotifications();
}
function out(x){document.getElementById('admin').innerHTML=`<main class="auth"><section class="card"><h1>WSID Admin</h1><p>${esc(x)}</p><a class="btn red" href="index.html">Kembali</a></section></main>`}
function draw(){
  const tabs=['dashboard','deposits','orders','services','connection','users','finance','reset','settings'];
  const labels={dashboard:'Dashboard',deposits:'Deposit',orders:'Riwayat',services:'Layanan',connection:'Koneksi',users:'Pantau User',finance:'Keuangan',reset:'Reset',settings:'Settings'};
  document.getElementById('admin').innerHTML=`<div class="shell admin-shell"><header><div class="brand"><i>W</i><b>WSID<small>ADMIN</small></b></div><div class="admin-actions"><button class="bell" onclick="tab='deposits';draw()">🔔<span id="depositBadge" class="notify-badge">0</span></button><button onclick="location.href='index.html'">↗</button></div></header><main><div class="tabs">${tabs.map(x=>`<button class="${tab===x?'on':''}" onclick="tab='${x}';draw()">${labels[x]}</button>`).join('')}</div><div id="view">Loading...</div></main></div>`;
  loadTab();
}
async function loadTab(){
  try{
    let r=tab==='dashboard'?dash():tab==='deposits'?deposits():tab==='orders'?orders():tab==='services'?services():tab==='connection'?connection():tab==='users'?users():tab==='finance'?finance():tab==='reset'?resetPanel():settings();
    document.getElementById('view').innerHTML=await r;
  }catch(e){document.getElementById('view').innerHTML=`<div class="card"><b>Gagal memuat</b><p>${esc(e.message||e)}</p></div>`;}
}
async function dash(){
  const u=await sb.from('profiles').select('*',{count:'exact',head:true}).eq('role','user');
  const o=await sb.from('orders').select('*',{count:'exact',head:true});
  const p=await sb.from('orders').select('profit');
  const d=await sb.from('deposits').select('amount',{count:'exact'}).eq('status','pending');
  const pending=d.count||0;
  return `<h1>Dashboard</h1><div class="stats"><div><small>User</small><b>${u.count||0}</b></div><div><small>Pesanan</small><b>${o.count||0}</b></div><div><small>Profit</small><b>${money((p.data||[]).reduce((a,x)=>a+Number(x.profit||0),0))}</b></div><div class="stat-alert"><small>Deposit Menunggu</small><b>${pending}</b></div></div>${pending?`<section class="admin-notice"><span class="notify-dot">!</span><div><b>${pending} deposit menunggu ACC</b><small>Periksa bukti pembayaran lalu lakukan ACC atau Tolak.</small></div><button class="btn red mini" onclick="tab='deposits';draw()">Lihat</button></section>`:''}<section class="card"><b>Pengaturan panel</b><p class="muted">DANA, branding, kontak, koneksi layanan, markup, dan notifikasi Telegram dapat dikelola dari panel ini.</p></section>`;
}
async function deposits(){
  const r=await sb.from('deposits').select('*,profiles:profiles!deposits_user_id_fkey(full_name,email)').order('created_at',{ascending:false});
  if(r.error)throw r.error;
  const rows=r.data||[];
  const signed=await Promise.all(rows.map(async d=>{
    if(!d.proof_path)return [d.id,''];
    const x=await sb.storage.from('deposit-proofs').createSignedUrl(d.proof_path,300);
    return [d.id,x.data?.signedUrl||''];
  }));
  const urls=Object.fromEntries(signed);
  const pending=rows.filter(x=>x.status==='pending').length;
  return `<div class="head"><h1>Deposit</h1><small>${pending} pengajuan menunggu ACC.</small></div><div class="list">${rows.map(d=>`<article class="admin-deposit-card"><span><b>${esc(d.profiles?.full_name||'User')}</b><small>${esc(d.profiles?.email||'')} • ${new Date(d.created_at).toLocaleString('id-ID')}</small><strong>${money(d.amount)}</strong>${urls[d.id]?`<a href="${urls[d.id]}" target="_blank" rel="noopener"><img class="admin-proof-thumb" src="${urls[d.id]}" alt="Bukti pembayaran"></a><a class="btn mini" href="${urls[d.id]}" target="_blank" rel="noopener">Lihat Bukti</a>`:''}</span><span><em class="status-badge status-${esc(d.status)}">${d.status==='pending'?'Menunggu ACC':d.status==='approved'?'Disetujui':'Ditolak'}</em>${d.status==='pending'?`<div class="row"><button class="btn mini red" onclick="review('${d.id}',true)">ACC</button><button class="btn mini danger" onclick="review('${d.id}',false)">Tolak</button></div>`:''}</span></article>`).join('')||'<div class="empty">Belum ada pengajuan deposit.</div>'}</div>`;
}
window.review=async(id,ok)=>{const r=await sb.rpc('review_deposit',{p_deposit_id:id,p_approve:ok});if(r.error)return alert(r.error.message);draw()};
async function orders(){
  const r=await sb.from('orders').select('*,profiles(full_name,email),services(name)').order('created_at',{ascending:false});
  if(r.error)throw r.error;
  const rows=r.data||[];
  return `<h1>Riwayat</h1><div class=\"history-search\"><input id=\"orderSearch\" placeholder=\"Cari ID riwayat...\" oninput=\"filterAdminHistory(this.value)\"></div><div id=\"adminHistoryList\" class=\"list\">${adminHistoryCards(rows)}</div>`;
}
function adminHistoryCards(rows){
  return (rows||[]).map(o=>{
    const code='WSO-'+String(o.id||'').replace(/-/g,'').slice(0,10).toUpperCase();
    return `<article class=\"admin-history-card\" data-id=\"${esc(o.id)}\"><span><b>${esc(code)}</b><small>${esc(o.profiles?.full_name||'User')} • ${esc(o.services?.name||'Layanan')}</small><small>Target: ${esc(o.target||'-')}</small></span><span><b>${money(o.sale_total)}</b><small>${esc(o.status||'pending')}</small><small>${new Date(o.created_at).toLocaleString('id-ID')}</small></span></article>`;
  }).join('')||'<div class=\"empty\">Belum ada riwayat order.</div>';
}
window.filterAdminHistory=q=>{
  const el=document.getElementById('adminHistoryList');if(!el)return;
  const v=String(q||'').trim().toLowerCase();
  [...el.children].forEach(x=>{x.style.display=(!v||String(x.dataset.id||'').toLowerCase().includes(v)||x.innerText.toLowerCase().includes(v))?'':'none';});
};

async function services(){
  const r=await sb.from('services').select('*').order('name');
  return `<h1>Layanan</h1><button class="btn red" onclick="sync()">Sync Layanan</button><div class="list">${(r.data||[]).map(s=>`<article><span><b>${esc(s.name)}</b><small>Biaya dasar ${money(s.provider_price)} • Jual ${money(s.sale_price)}</small></span><button class="btn mini" onclick="markup('${s.id}',${Number(s.markup_value||0)},'${esc(s.markup_type||'percent')}')">Markup</button></article>`).join('')||'<div class="empty">Belum ada layanan.</div>'}</div>`;
}
window.markup=async(id,v,t)=>{const x=prompt('Markup '+(t==='percent'?'%':'Rp'),v);if(x===null)return;const r=await sb.rpc('set_service_markup',{p_service_id:id,p_markup_type:t,p_markup_value:Number(x)});if(r.error)alert(r.error.message);draw()};
window.sync=async()=>{const el=document.getElementById('pm');if(el)el.textContent='Sinkronisasi layanan...';const r=await edge({action:'sync_services'});if(el)el.textContent=r.status?`Sync berhasil: ${r.count} layanan`:('Gagal: '+(r.msg||JSON.stringify(r)));alert(r.status?`Sync berhasil: ${r.count} layanan`:('Gagal: '+(r.msg||'Terjadi kesalahan')))};
async function connection(){
  const r=await sb.from('providers').select('*').eq('name','FAYUPEDIA').maybeSingle();
  const p=r.data||{name:'FAYUPEDIA',base_url:'https://fayupedia.id/api',api_id:'',api_key:'',default_markup_type:'percent',default_markup_value:0,is_active:true};
  return `<h1>Koneksi</h1><section class="card"><h3>Koneksi Layanan</h3><p class="muted">Pengaturan koneksi disimpan di database dan tidak perlu diedit di config.js.</p><label>Base URL<input id="pu" value="${esc(p.base_url)}"></label><label>ID Koneksi<input id="pi" value="${esc(p.api_id)}" autocomplete="off"></label><label>Kunci Koneksi<input id="pk" type="password" value="${esc(p.api_key||'')}" autocomplete="off"></label><label>Markup Default<select id="pt"><option value="percent" ${p.default_markup_type==='percent'?'selected':''}>Persen (%)</option><option value="fixed" ${p.default_markup_type==='fixed'?'selected':''}>Tetap (Rp)</option></select></label><label>Nilai Markup<input id="pv" type="number" value="${Number(p.default_markup_value||0)}"></label><label class="check"><input id="pa" type="checkbox" ${p.is_active!==false?'checked':''}> Koneksi aktif</label><div class="row"><button class="btn red" onclick="saveConnection()">Simpan Koneksi</button><button class="btn" onclick="testConnection()">Tes Koneksi</button></div><button class="btn wide" onclick="sync()">Sync Layanan</button><p id="pm" class="msg"></p></section>`;
}
window.saveConnection=async()=>{const g=id=>document.getElementById(id);const existing=await sb.from('providers').select('id,api_key').eq('name','FAYUPEDIA').maybeSingle();const u=(await sb.auth.getUser()).data.user;const row={name:'FAYUPEDIA',base_url:g('pu').value.trim(),api_id:g('pi').value.trim(),api_key:g('pk').value||existing.data?.api_key||'',default_markup_type:g('pt').value,default_markup_value:Number(g('pv').value||0),is_active:g('pa').checked,updated_at:new Date().toISOString(),updated_by:u?.id||null};if(existing.data?.id)row.id=existing.data.id;const r=await sb.from('providers').upsert(row,{onConflict:'id'});if(r.error)return alert(r.error.message);alert('Pengaturan koneksi tersimpan.');draw()};
window.testConnection=async()=>{const el=document.getElementById('pm');if(el)el.textContent='Menghubungkan...';const r=await edge({action:'balance'});if(el)el.textContent=r.balance!==undefined?`Koneksi berhasil • Saldo: ${r.balance}`:('Gagal: '+(r.msg||JSON.stringify(r)))};
async function users(){
  const [r,w,l]=await Promise.all([
    sb.from('profiles').select('id,full_name,email,role,created_at').order('created_at',{ascending:false}),
    sb.from('wallets').select('user_id,balance'),
    sb.from('login_events').select('user_id,created_at').order('created_at',{ascending:false}).limit(1000)
  ]);
  if(r.error)throw r.error;
  const balances=Object.fromEntries((w.data||[]).map(x=>[x.user_id,x.balance]));
  const last={};(l.data||[]).forEach(x=>{if(!last[x.user_id])last[x.user_id]=x.created_at});
  const rows=r.data||[]; const memberCount=rows.filter(x=>x.role==='user').length;
  const totalBalance=rows.reduce((a,x)=>a+Number(balances[x.id]||0),0);
  return `<div class="head"><h1>Pantau User</h1><small>${memberCount} user terdaftar • ${money(totalBalance)} total saldo</small></div>
  <div class="stats"><div><small>Total User</small><b>${memberCount}</b></div><div><small>Total Saldo</small><b>${money(totalBalance)}</b></div></div>
  <div class="history-search"><input id="userSearch" placeholder="Cari nama, email atau ID user..." oninput="filterUsers(this.value)"></div>
  <div class="list" id="userList">${rows.map(x=>`<article class="admin-user-card" data-search="${esc((x.full_name||'')+' '+(x.email||'')+' '+x.id)}"><span><b>${esc(x.full_name||'Member')}</b><small>${esc(x.email||'-')} • ${esc(x.role)}</small><small>ID: ${esc(x.id)}</small><small>Daftar: ${new Date(x.created_at).toLocaleString('id-ID')}</small><strong>Saldo: ${money(balances[x.id]||0)}</strong><small>${last[x.id]?'Login terakhir: '+new Date(last[x.id]).toLocaleString('id-ID'):'Belum ada catatan login'}</small></span><span class="row"><button class="btn mini red" onclick="adjustBalance('${x.id}','${esc(x.full_name||'Member')}',1)">+ Saldo</button><button class="btn mini" onclick="adjustBalance('${x.id}','${esc(x.full_name||'Member')}',-1)">− Saldo</button></span></article>`).join('')||'<div class="empty">Belum ada user.</div>'}</div>`;
}
window.filterUsers=q=>{const v=String(q||'').toLowerCase();document.querySelectorAll('#userList .admin-user-card').forEach(x=>x.style.display=(!v||x.dataset.search.toLowerCase().includes(v))?'':'none')};
window.adjustBalance=async(id,name,dir)=>{const label=dir>0?'Tambah saldo':'Kurangi saldo';const raw=prompt(`${label} untuk ${name}\nMasukkan nominal tanpa titik/koma:`, '2000');if(raw===null)return;const amount=Number(String(raw).replace(/[^0-9.-]/g,''));if(!Number.isFinite(amount)||amount<=0)return alert('Nominal tidak valid.');const note=prompt('Keterangan (opsional):',label);const r=await sb.rpc('admin_adjust_balance',{p_user_id:id,p_amount:dir*amount,p_description:note||label});if(r.error)return alert(r.error.message);alert(`${label} berhasil. Saldo sekarang: ${money(r.data)}`);draw()};


async function finance(){
  const w=await sb.from('wallets').select('balance'),o=await sb.from('orders').select('provider_cost,sale_total,profit');
  return `<h1>Keuangan</h1><div class="stats"><div><small>Saldo User</small><b>${money((w.data||[]).reduce((a,x)=>a+Number(x.balance),0))}</b></div><div><small>Biaya Dasar</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.provider_cost),0))}</b></div><div><small>Profit</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.profit),0))}</b></div></div>`;
}
async function resetPanel(){
  return `<h1>Reset</h1>
  <section class="card reset-card"><h3>⚠️ Reset Data Panel</h3><p class="muted">Setiap fitur di bawah berdiri sendiri. Akun user, layanan, koneksi, dan Settings tidak ikut dihapus kecuali yang tertulis pada tombol.</p>
  <div class="reset-grid">
    <button class="reset-item" onclick="runReset('profit','Reset semua profit? Profit pada riwayat order akan diubah menjadi Rp0.')"><b>💰 Reset Profit</b><small>Set semua profit order menjadi Rp0.</small></button>
    <button class="reset-item" onclick="runReset('balance','Reset semua saldo user? Semua saldo akan menjadi Rp0.')"><b>💳 Reset Saldo User</b><small>Semua saldo wallet user menjadi Rp0.</small></button>
    <button class="reset-item" onclick="runReset('orders','Hapus semua riwayat order? Tindakan ini tidak dapat dibatalkan.')"><b>🛒 Reset Riwayat Order</b><small>Hapus seluruh data order.</small></button>
    <button class="reset-item" onclick="runReset('deposits','Hapus semua riwayat deposit? Tindakan ini tidak dapat dibatalkan.')"><b>🏦 Reset Riwayat Deposit</b><small>Hapus seluruh pengajuan deposit.</small></button>
    <button class="reset-item" onclick="runReset('transactions','Hapus semua transaksi? Tindakan ini tidak dapat dibatalkan.')"><b>📒 Reset Transaksi</b><small>Hapus seluruh catatan transaksi saldo.</small></button>
    <button class="reset-item" onclick="runReset('logins','Hapus semua catatan login user?')"><b>🔐 Reset Aktivitas Login</b><small>Hapus seluruh riwayat login.</small></button>
    <button class="reset-item danger-reset" onclick="runReset('all_activity','RESET SEMUA DATA AKTIVITAS? Order, deposit, transaksi, login dan saldo akan direset. Akun user tetap ada.')"><b>🔥 Reset Semua Data Aktivitas</b><small>Membersihkan data aktivitas tetapi akun user tetap dipertahankan.</small></button>
  </div></section>`;
}
window.runReset=async(target,message)=>{
  if(!confirm(message))return;
  const confirm2=target==='all_activity'||['orders','deposits','transactions'].includes(target)?prompt('Ketik RESET untuk melanjutkan:',''):null;
  if(confirm2!==null && confirm2!=='RESET')return alert('Reset dibatalkan.');
  const r=await sb.rpc('admin_reset_panel_data',{p_target:target});
  if(r.error)return alert(r.error.message);
  alert(r.data?.message||'Reset berhasil.'); draw();
};

async function settings(){
  const [r,tg]=await Promise.all([sb.from('panel_settings').select('*'),sb.from('telegram_config').select('bot_token,chat_id').eq('id',1).maybeSingle()]);const v={};(r.data||[]).forEach(x=>v[x.key]=x.value);if(tg.data){v.telegram_bot_token=tg.data.bot_token||'';if(tg.data.chat_id)v.telegram_chat_id=tg.data.chat_id;}
  return `<h1>Settings</h1><section class=\"card\"><h3>Branding & Kontak</h3>
  <label>Nama Panel<input id=\"sn\" value=\"${esc(v.panel_name||'WSID SMM PANEL')}\"></label>
  <label>Nama Owner<input id=\"so\" value=\"${esc(v.owner_name||'Witama Store.ID')}\"></label>
  <label>Nomor DANA<input id=\"sd\" value=\"${esc(v.dana_number||'')}\"></label>
  <label>Nama DANA<input id=\"sda\" value=\"${esc(v.dana_name||'Witama Store.ID')}\"></label>
  <h3 class=\"settings-subtitle\">QRIS</h3>
  <div class=\"qris-admin-box\">${v.qris_image_url?`<img src=\"${esc(v.qris_image_url)}\" class=\"qris-admin-preview\" alt=\"QRIS\">`: '<div class=\"empty\">Belum ada foto QRIS.</div>'}
  <label class=\"upload-box admin-upload\"><span>↑</span><b>Pilih foto QRIS</b><small id=\"qris-name\">JPG, PNG atau WEBP • maksimal 2MB</small><input id=\"qrisFile\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\" onchange=\"showQrisName(this)\"></label></div>
  <label>WhatsApp Support<input id=\"sw\" value=\"${esc(v.support_whatsapp||'')}\"></label>
  <label>Telegram Support<input id=\"st\" value=\"${esc(v.support_telegram||'')}\"></label>
  <label>Instagram Support<input id=\"si\" value=\"${esc(v.support_instagram||'')}\"></label>
  <h3 class=\"settings-subtitle\">Notifikasi Telegram</h3>
  <label>Token Bot Telegram<input id="tb" type="text" value="${esc(v.telegram_bot_token||'')}" placeholder="Masukkan token bot Telegram"></label>
  <label>ID Telegram Admin / Test<input id="tc" value="${esc(v.telegram_chat_id||'')}" placeholder="Contoh: 123456789"></label>
  <label>Channel / Grup Notifikasi<input id="tnc" value="${esc(v.telegram_notify_chat_id||'')}" placeholder="Contoh: @channelkamu atau -1001234567890"></label>
  <label>Username Bot Telegram<input id="tbu" value="${esc(v.telegram_bot_username||'')}" placeholder="Contoh: UbotWSID"></label>
  <small class="muted">Token digunakan untuk notifikasi panel ke Telegram dan hanya dapat diubah dari area Admin. Pastikan bot sudah menjadi admin di channel/grup tujuan.</small>
  <div class=\"row\"><button class=\"btn red\" onclick=\"saveSettings()\">Simpan Settings</button><button class=\"btn\" onclick=\"testTelegram()\">Tes Telegram</button></div><p id=\"sm\" class=\"msg\"></p></section>`;
}
window.showQrisName=input=>{const f=input?.files?.[0],el=document.getElementById('qris-name');if(el)el.textContent=f?`File dipilih: ${f.name}`:'JPG, PNG atau WEBP • maksimal 2MB';};
window.saveSettings=async()=>{
  try{
    const map={panel_name:document.getElementById('sn').value,owner_name:document.getElementById('so').value,dana_number:document.getElementById('sd').value,dana_name:document.getElementById('sda').value,support_whatsapp:document.getElementById('sw').value,support_telegram:document.getElementById('st').value,support_instagram:document.getElementById('si').value,telegram_chat_id:document.getElementById('tc').value.trim(),telegram_notify_chat_id:document.getElementById('tnc').value.trim(),telegram_bot_username:document.getElementById('tbu').value.trim()};
    const telegramToken=document.getElementById('tb')?.value.trim(); const telegramChat=document.getElementById('tc')?.value.trim();
    if(telegramToken||telegramChat){const meTelegram=(await sb.auth.getUser()).data.user?.id||null;const tg=await sb.from('telegram_config').upsert({id:1,bot_token:telegramToken||null,chat_id:telegramChat||null,updated_by:meTelegram,updated_at:new Date().toISOString()},{onConflict:'id'});if(tg.error)throw tg.error;}
    const qf=document.getElementById('qrisFile')?.files?.[0];
    if(qf){
      if(qf.size>2*1024*1024)return alert('Ukuran QRIS maksimal 2MB.');
      const path=`qris/${Date.now()}-${qf.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
      const u=await sb.storage.from('panel-assets').upload(path,qf,{upsert:false,contentType:qf.type});
      if(u.error)throw u.error;
      const pub=sb.storage.from('panel-assets').getPublicUrl(path);
      map.qris_image_url=pub.data.publicUrl;
    }
    const rows=Object.entries(map).map(([key,value])=>({key,value,updated_by:null,updated_at:new Date().toISOString()}));
    const me=(await sb.auth.getUser()).data.user;rows.forEach(x=>x.updated_by=me?.id||null);
    const r=await sb.from('panel_settings').upsert(rows,{onConflict:'key'});
    if(r.error)throw r.error;
    alert('Settings tersimpan.');draw();
  }catch(e){alert(e?.message||'Gagal menyimpan settings.');}
};
window.testTelegram=async()=>{
  const chat=document.getElementById('tnc')?.value.trim()||document.getElementById('tc')?.value.trim();
  const token=document.getElementById('tb')?.value.trim();
  if(!token)return alert('Isi Token Bot Telegram dulu.');
  if(!chat)return alert('Isi ID Telegram dulu.');
  const me=(await sb.auth.getUser()).data.user?.id||null;
  const save=await sb.from('telegram_config').upsert({id:1,bot_token:token,chat_id:chat,updated_by:me,updated_at:new Date().toISOString()},{onConflict:'id'});
  if(save.error)return alert(save.error.message);
  const r=await sb.rpc('test_telegram_deposit_notification');
  if(r.error)return alert(r.error.message);
  alert(r.data?.msg||'Notifikasi Telegram dikirim.');
};

async function updateDepositNotification(showToast=true){
  const r=await sb.from('deposits').select('id',{count:'exact',head:true}).eq('status','pending');
  if(r.error)return;
  const count=r.count||0;const badge=document.getElementById('depositBadge');
  if(badge){badge.textContent=count;badge.style.display=count?'grid':'none';}
  if(showToast&&lastPendingDeposits!==null&&count>lastPendingDeposits){const diff=count-lastPendingDeposits;const toast=document.createElement('div');toast.className='admin-toast';toast.innerHTML=`<b>🔔 Deposit baru masuk</b><small>${diff} pengajuan deposit menunggu ACC.</small><button class="btn mini red" onclick="this.parentElement.remove();tab='deposits';draw()">Periksa</button>`;document.body.appendChild(toast);setTimeout(()=>toast.remove(),9000)}
  lastPendingDeposits=count;
}
function startDepositNotifications(){clearInterval(depositPoll);updateDepositNotification(false);depositPoll=setInterval(()=>updateDepositNotification(true),15000)}
async function edge(body){const r=await sb.rpc('provider_call',{p_action:body.action});if(r.error)return{status:false,msg:r.error.message};return r.data||{status:false,msg:'Respon kosong'}}
init();
