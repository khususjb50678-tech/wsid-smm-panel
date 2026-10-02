const C=window.WSID_CONFIG||{};
const money=n=>new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(n||0));
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let tab='dashboard',generatedApi=null;

async function init(){
  if(!sb)return out('Isi koneksi Supabase di config.js.');
  const q=await sb.auth.getSession();
  if(!q.data.session)return location.href='login.html';
  const p=await sb.from('profiles').select('*').eq('id',q.data.session.user.id).single();
  if(p.data?.role!=='admin')return out('Akses admin ditolak.');
  draw();
}
function out(x){document.getElementById('admin').innerHTML=`<main class="auth"><section class="card"><h1>WSID Admin</h1><p>${esc(x)}</p><a class="btn red" href="index.html">Kembali</a></section></main>`}
function draw(){
  const tabs=['dashboard','deposits','orders','services','provider','users','finance','settings','api-docs'];
  document.getElementById('admin').innerHTML=`<div class="shell"><header><div class="brand"><i>W</i><b>WSID<small>ADMIN</small></b></div><button onclick="location.href='index.html'">↗</button></header><main><div class="tabs">${tabs.map(x=>`<button class="${tab===x?'on':''}" onclick="tab='${x}';draw()">${x==='api-docs'?'API Docs':x}</button>`).join('')}</div><div id="view">Loading...</div></main></div>`;
  loadTab();
}
async function loadTab(){
  try{let r=tab==='dashboard'?dash():tab==='deposits'?deposits():tab==='orders'?orders():tab==='services'?services():tab==='provider'?provider():tab==='users'?users():tab==='finance'?finance():tab==='settings'?settings():apiDocs();document.getElementById('view').innerHTML=await r;}catch(e){document.getElementById('view').innerHTML=`<div class="card"><b>Gagal memuat</b><p>${esc(e.message||e)}</p></div>`;}}
async function dash(){let u=await sb.from('profiles').select('*',{count:'exact',head:true}).eq('role','user'),o=await sb.from('orders').select('*',{count:'exact',head:true}),p=await sb.from('orders').select('profit');return `<h1>Dashboard</h1><div class="stats"><div><small>User</small><b>${u.count||0}</b></div><div><small>Order</small><b>${o.count||0}</b></div><div><small>Profit</small><b>${money((p.data||[]).reduce((a,x)=>a+Number(x.profit||0),0))}</b></div></div><section class="card"><b>Pengaturan sekarang</b><p class="muted">API provider, DANA, branding, kontak, markup default, dan kredensial API user dapat dikelola langsung dari panel ini.</p></section>`}
async function deposits(){let r=await sb.from('deposits').select('*,profiles(full_name,email)').order('created_at',{ascending:false});return `<h1>Deposit</h1><div class="list">${(r.data||[]).map(d=>`<article><span><b>${esc(d.profiles?.full_name)}</b><small>${money(d.amount)} • ${esc(d.status)}</small></span>${d.status==='pending'?`<span><button class="btn mini" onclick="review('${d.id}',true)">ACC</button><button class="btn mini danger" onclick="review('${d.id}',false)">Tolak</button></span>`:''}</article>`).join('')||'<div class="empty">Kosong.</div>'}</div>`}
window.review=async(id,ok)=>{let r=await sb.rpc('review_deposit',{p_deposit_id:id,p_approve:ok});if(r.error)alert(r.error.message);draw()};
async function orders(){let r=await sb.from('orders').select('*,profiles(full_name),services(name)').order('created_at',{ascending:false});return `<h1>Orders</h1><div class="list">${(r.data||[]).map(o=>`<article><span><b>${esc(o.profiles?.full_name)}</b><small>${esc(o.services?.name)} • ${esc(o.target)}</small></span><span><b>${money(o.sale_total)}</b><small>${esc(o.status)}</small></span></article>`).join('')||'<div class="empty">Belum ada order.</div>'}</div>`}
async function services(){let r=await sb.from('services').select('*').order('name');return `<h1>Services</h1><button class="btn red" onclick="sync()">Sync Services</button><div class="list">${(r.data||[]).map(s=>`<article><span><b>${esc(s.name)}</b><small>Provider ${money(s.provider_price)} • Jual ${money(s.sale_price)}</small></span><button class="btn mini" onclick="markup('${s.id}',${Number(s.markup_value||0)},'${esc(s.markup_type||'percent')}')">Markup</button></article>`).join('')||'<div class="empty">Belum ada service.</div>'}</div>`}
window.markup=async(id,v,t)=>{let x=prompt('Markup '+(t==='percent'?'%':'Rp'),v);if(x===null)return;let r=await sb.rpc('set_service_markup',{p_service_id:id,p_markup_type:t,p_markup_value:Number(x)});if(r.error)alert(r.error.message);draw()};
window.sync=async()=>{const r=await edge({action:'sync_services'});alert(r.msg||'Selesai');draw()};
async function provider(){
  const r=await sb.from('providers').select('*').eq('name','FAYUPEDIA').maybeSingle();
  const p=r.data||{name:'FAYUPEDIA',base_url:'https://fayupedia.id/api',api_id:'',api_key:'',default_markup_type:'percent',default_markup_value:0,is_active:true};
  return `<h1>Provider</h1><section class="card"><h3>Provider API</h3><p class="muted">Semua kredensial sekarang disimpan di database Supabase dan dikelola dari panel. Tidak perlu bolak-balik ke config.js.</p><label>Nama Provider<input id="pn" value="${esc(p.name)}"></label><label>Base URL API<input id="pu" value="${esc(p.base_url)}"></label><label>API ID<input id="pi" value="${esc(p.api_id)}" autocomplete="off"></label><label>API Key<input id="pk" type="password" value="${esc(p.api_key||'')}" autocomplete="off"></label><label>Markup Default<select id="pt"><option value="percent" ${p.default_markup_type==='percent'?'selected':''}>Persen (%)</option><option value="fixed" ${p.default_markup_type==='fixed'?'selected':''}>Tetap (Rp)</option></select></label><label>Nilai Markup<input id="pv" type="number" value="${Number(p.default_markup_value||0)}"></label><label class="check"><input id="pa" type="checkbox" ${p.is_active!==false?'checked':''}> Provider aktif</label><div class="row"><button class="btn red" onclick="saveProvider()">Simpan API Provider</button><button class="btn" onclick="test()">Test Connection</button></div><button class="btn wide" onclick="sync()">Sync Services</button><p id="pm" class="msg"></p></section>`;
}
window.saveProvider=async()=>{const g=id=>document.getElementById(id);const existing=await sb.from('providers').select('id,api_key').eq('name','FAYUPEDIA').maybeSingle();const u=(await sb.auth.getUser()).data.user;const row={name:g('pn').value.trim(),base_url:g('pu').value.trim(),api_id:g('pi').value.trim(),api_key:g('pk').value||existing.data?.api_key||'',default_markup_type:g('pt').value,default_markup_value:Number(g('pv').value||0),is_active:g('pa').checked,updated_at:new Date().toISOString(),updated_by:u?.id||null};if(existing.data?.id)row.id=existing.data.id;const r=await sb.from('providers').upsert(row,{onConflict:'id'});if(r.error)return alert(r.error.message);alert('Pengaturan provider tersimpan.');draw()};
window.test=async()=>{const el=document.getElementById('pm');if(el)el.textContent='Menghubungkan...';const r=await edge({action:'balance'});if(el)el.textContent=r.balance!==undefined?`Koneksi berhasil • Saldo provider: ${r.balance}`:(r.msg||'Gagal terhubung')};
async function users(){let r=await sb.from('profiles').select('*').order('created_at',{ascending:false});return `<h1>Users</h1>${generatedApi?`<section class="card api-new"><b>API Key baru untuk ${esc(generatedApi.name)}</b><small>Simpan sekarang. Key ini tidak disimpan dalam bentuk teks di database.</small><pre>${esc(generatedApi.api_key)}</pre><button class="btn" onclick="navigator.clipboard?.writeText('${esc(generatedApi.api_key)}');alert('API Key disalin')">Salin API Key</button></section>`:''}<div class="list">${(r.data||[]).map(x=>`<article><span><b>${esc(x.full_name)}</b><small>${esc(x.email)} • ${esc(x.role)}${x.api_id?` • ${esc(x.api_id)}`:''}</small></span><button class="btn mini" onclick="generateApi('${x.id}','${esc(x.full_name||x.email)}')">${x.api_id?'Reset API':'Buat API'}</button></article>`).join('')}</div>`}
function randomToken(prefix,len=30){const a=new Uint8Array(len);crypto.getRandomValues(a);return prefix+Array.from(a).map(x=>(x%36).toString(36)).join('')}
window.generateApi=async(id,name)=>{if(!confirm('Generate API key baru untuk user ini? Key lama akan tidak berlaku.'))return;const api_id='wsid_'+randomToken('',10);const api_key='wskey_'+randomToken('',34);const r=await sb.rpc('set_user_api_key',{p_user_id:id,p_api_id:api_id,p_api_key:api_key});if(r.error)return alert(r.error.message);generatedApi={name,api_id,api_key};draw()};
async function finance(){let w=await sb.from('wallets').select('balance'),o=await sb.from('orders').select('provider_cost,sale_total,profit');return `<h1>Keuangan</h1><div class="stats"><div><small>Saldo User</small><b>${money((w.data||[]).reduce((a,x)=>a+Number(x.balance),0))}</b></div><div><small>Biaya Provider</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.provider_cost),0))}</b></div><div><small>Profit</small><b>${money((o.data||[]).reduce((a,x)=>a+Number(x.profit),0))}</b></div></div><div class="notice">Profit adalah selisih harga jual panel dan biaya provider. Dana provider tetap berada pada akun provider.</div>`}
async function settings(){let r=await sb.from('panel_settings').select('*');const v={};(r.data||[]).forEach(x=>v[x.key]=x.value);return `<h1>Settings</h1><section class="card"><h3>Branding & Kontak</h3><label>Nama Panel<input id="sn" value="${esc(v.panel_name||'WSID SMM PANEL')}"></label><label>Nama Owner<input id="so" value="${esc(v.owner_name||'Witama Store.ID')}"></label><label>Nomor DANA<input id="sd" value="${esc(v.dana_number||'')}"></label><label>Nama DANA<input id="sda" value="${esc(v.dana_name||'Witama Store.ID')}"></label><label>URL QRIS<input id="sq" value="${esc(v.qris_image_url||'')}"></label><label>WhatsApp Support<input id="sw" value="${esc(v.support_whatsapp||'')}"></label><label>Telegram Support<input id="st" value="${esc(v.support_telegram||'')}"></label><label>Instagram Support<input id="si" value="${esc(v.support_instagram||'')}"></label><button class="btn red wide" onclick="saveSettings()">Simpan Semua Settings</button><p id="sm" class="msg"></p></section>`}
window.saveSettings=async()=>{const map={panel_name:document.getElementById('sn').value,owner_name:document.getElementById('so').value,dana_number:document.getElementById('sd').value,dana_name:document.getElementById('sda').value,qris_image_url:document.getElementById('sq').value,support_whatsapp:document.getElementById('sw').value,support_telegram:document.getElementById('st').value,support_instagram:document.getElementById('si').value};const rows=Object.entries(map).map(([key,value])=>({key,value,updated_by:null,updated_at:new Date().toISOString()}));const me=(await sb.auth.getUser()).data.user;rows.forEach(x=>x.updated_by=me?.id||null);const r=await sb.from('panel_settings').upsert(rows,{onConflict:'key'});if(r.error)return alert(r.error.message);alert('Semua settings tersimpan.');draw()};
function apiDocs(){const endpoint=`${C.SUPABASE_URL}/functions/v1/wsid-api`;return `<h1>API Docs</h1><section class="card"><p>API publik WSID SMM PANEL. Tidak menampilkan nama provider internal.</p><label>Endpoint</label><pre>${endpoint}</pre><h3>Autentikasi</h3><pre>api_id=YOUR_API_ID
api_key=YOUR_API_KEY</pre><h3>Services</h3><pre>POST ${endpoint}
{
  "api_id":"YOUR_API_ID",
  "api_key":"YOUR_API_KEY",
  "action":"services"
}</pre><h3>Order</h3><pre>POST ${endpoint}
{
  "api_id":"YOUR_API_ID",
  "api_key":"YOUR_API_KEY",
  "action":"order",
  "service":"SERVICE_ID",
  "target":"@username",
  "quantity":1000
}</pre><h3>Status</h3><pre>POST ${endpoint}
{
  "api_id":"YOUR_API_ID",
  "api_key":"YOUR_API_KEY",
  "action":"status",
  "id":"ORDER_ID"
}</pre><h3>Refill</h3><pre>POST ${endpoint}
{
  "api_id":"YOUR_API_ID",
  "api_key":"YOUR_API_KEY",
  "action":"refill",
  "id":"ORDER_ID"
}</pre><h3>Refill Status</h3><pre>POST ${endpoint}
{
  "api_id":"YOUR_API_ID",
  "api_key":"YOUR_API_KEY",
  "action":"refill_status",
  "id":"ORDER_ID"
}</pre><div class="notice">API key user dibuat dari menu Users. Key hanya ditampilkan saat dibuat/reset.</div></section>`}
async function edge(body){const s=(await sb.auth.getSession()).data.session;if(!s)throw new Error('Session habis. Login ulang.');const r=await fetch(`${C.SUPABASE_URL}/functions/v1/provider-fayupedia`,{method:'POST',headers:{Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json'},body:JSON.stringify(body)});return r.json()}
init();
