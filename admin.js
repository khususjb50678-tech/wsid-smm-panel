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
  const tabs=['dashboard','deposits','orders','services','connection','users','finance','settings'];
  const labels={dashboard:'Dashboard',deposits:'Deposit',orders:'Pesanan',services:'Layanan',connection:'Koneksi',users:'Users',finance:'Keuangan',settings:'Settings'};
  document.getElementById('admin').innerHTML=`<div class="shell admin-shell"><header><div class="brand"><i>W</i><b>WSID<small>ADMIN</small></b></div><div class="admin-actions"><button class="bell" onclick="tab='deposits';draw()">🔔<span id="depositBadge" class="notify-badge">0</span></button><button onclick="location.href='index.html'">↗</button></div></header><main><div class="tabs">${tabs.map(x=>`<button class="${tab===x?'on':''}" onclick="tab='${x}';draw()">${labels[x]}</button>`).join('')}</div><div id="view">Loading...</div></main></div>`;
  loadTab();
}
async function loadTab(){
  try{
    let r=tab==='dashboard'?dash():tab==='deposits'?deposits():tab==='orders'?orders():tab==='services'?services():tab==='connection'?connection():tab==='users'?users():tab==='finance'?finance():settings();
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
  const r=await sb.from('deposits').select('*,profiles(full_name,email)').order('created_at',{ascending:false});
  if(r.error)throw r.error;
  const rows=r.data||[];
  const signed=await Promise.all(rows.map(async d=>{
    if(!d.proof_path)return [d.id,''];
    const x=await sb.storage.from('deposit-proofs').createSignedUrl(d.proof_path,300);
    return [d.id,x.data?.signedUrl||''];
  }));
  const urls=Object.fromEntries(signed);
  const pending=rows.filter(x=>x.status==='pending').length;
  return `<div class="head"><h1>Deposit</h1><small>${pending} pengajuan menunggu ACC.</small></div><div class="list">${rows.map(d=>`<article class="admin-deposit-card"><span><b>${esc(d.profiles?.full_name||'User')}</b><small>${esc(d.profiles?.email||'')} • ${new Date(d.created_at).toLocaleString('id-ID')}</small><strong>${money(d.amount)}</strong>${urls[d.id]?`<a class="btn mini" href="${urls[d.id]}" target="_blank" rel="noopener">Lihat Bukti</a>`:''}</span><span><em class="status-badge status-${esc(d.status)}">${d.status==='pending'?'Menunggu ACC':d.status==='approved'?'Disetujui':'Ditolak'}</em>${d.status==='pending'?`<div class="row"><button class="btn mini red" onclick="review('${d.id}',true)">ACC</button><button class="btn mini danger" onclick="review('${d.id}',false)">Tolak</button></div>`:''}</span></article>`).join('')||'<div class="empty">Belum ada pengajuan deposit.</div>'}</div>`;
}
window.review=async(id,ok)=>{const r=await sb.rpc('review_deposit',{p_deposit_id:id,p_approve:ok});if(r.error)return alert(r.error.message);draw()};
async function orders(){
  const r=await sb.from('orders').select('*,profiles(full_name),services(name)').order('created_at',{ascending:false});
  return `<h1>Pesanan</h1><div class="list">${(r.data||[]).map(o=>`<article><span><b>${esc(o.profiles?.full_name)}</b><small>${esc(o.services?.name)} • ${esc(o.target)}</small></span><span><b>${money(o.sale_total)}</b><small>${esc(o.status)}</small></span></article>`).join('')||'<div class="empty">Belum ada pesanan.</div>'}</div>`;
}
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
  const r=await sb.from('profiles').select('id,full_name,email,role,created_at').order('created_at',{ascending:false});
  return `<h1>Users</h1><div class="list">${(r.data||[]).map(x=>`<article><span><b>${esc(x.full_name)}</b><small>${esc(x.email)} • ${esc(x.role)}</small></span></article>`).join('')||'<div class="empty">Belum ada user.</div>'}</div>`;
}
async function finance(){
  const w=await sb.from('wallets').select('balance'),o=await sb.from('orders').select('provider_cost,sale_total,profit');
  return `<h1>Keuangan</h1><div class="stats"><div><small>Saldo User</small><b>${money((w.data||[]).reduce((a,x)=>a+Number(x.balance),0))}</b></div><div><small>Biaya Dasar</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.provider_cost),0))}</b></div><div><small>Profit</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.profit),0))}</b></div></div>`;
}
async function settings(){
  const r=await sb.from('panel_settings').select('*');const v={};(r.data||[]).forEach(x=>v[x.key]=x.value);
  return `<h1>Settings</h1><section class="card"><h3>Branding & Kontak</h3><label>Nama Panel<input id="sn" value="${esc(v.panel_name||'WSID SMM PANEL')}"></label><label>Nama Owner<input id="so" value="${esc(v.owner_name||'Witama Store.ID')}"></label><label>Nomor DANA<input id="sd" value="${esc(v.dana_number||'')}"></label><label>Nama DANA<input id="sda" value="${esc(v.dana_name||'Witama Store.ID')}"></label><label>URL QRIS<input id="sq" value="${esc(v.qris_image_url||'')}"></label><label>WhatsApp Support<input id="sw" value="${esc(v.support_whatsapp||'')}"></label><label>Telegram Support<input id="st" value="${esc(v.support_telegram||'')}"></label><label>Instagram Support<input id="si" value="${esc(v.support_instagram||'')}"></label><h3 class="settings-subtitle">Notifikasi Telegram</h3><label>Telegram Chat ID<input id="tc" value="${esc(v.telegram_chat_id||'')}" placeholder="Contoh: 123456789"></label><small class="muted">Token bot disimpan sebagai secret di Supabase, bukan di website.</small><button class="btn red wide" onclick="saveSettings()">Simpan Semua Settings</button><p id="sm" class="msg"></p></section>`;
}
window.saveSettings=async()=>{const map={panel_name:document.getElementById('sn').value,owner_name:document.getElementById('so').value,dana_number:document.getElementById('sd').value,dana_name:document.getElementById('sda').value,qris_image_url:document.getElementById('sq').value,support_whatsapp:document.getElementById('sw').value,support_telegram:document.getElementById('st').value,support_instagram:document.getElementById('si').value,telegram_chat_id:document.getElementById('tc').value.trim()};const rows=Object.entries(map).map(([key,value])=>({key,value,updated_by:null,updated_at:new Date().toISOString()}));const me=(await sb.auth.getUser()).data.user;rows.forEach(x=>x.updated_by=me?.id||null);const r=await sb.from('panel_settings').upsert(rows,{onConflict:'key'});if(r.error)return alert(r.error.message);alert('Semua settings tersimpan.');draw()};
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
