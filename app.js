const C=window.WSID_CONFIG||{};
const S={page:'home',user:null,profile:null,wallet:{balance:0},services:[],settings:{}};
const setting=(k,f='')=>S.settings?.[k]??f;

const money=n=>new Intl.NumberFormat('id-ID',{
  style:'currency',currency:'IDR',maximumFractionDigits:0
}).format(Number(n||0));

const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[c]));

// Bersihkan deskripsi layanan dari HTML agar tidak tampil sebagai tag mentah.
const cleanText=x=>{
  let raw=String(x??'')
    .replace(/<br\s*\/?>(?=\s*)/gi,'\n')
    .replace(/<\/(p|div|li|h[1-6])>/gi,'\n')
    .replace(/<[^>]*>/g,' ');
  const box=document.createElement('textarea');
  box.innerHTML=raw;
  return box.value.replace(/\u00a0/g,' ').replace(/[ \t]+\n/g,'\n').replace(/\n{3,}/g,'\n\n').trim();
};
const formatRules=x=>{
  const t=cleanText(x||'').replace(/\r/g,'').replace(/[•●▪]/g,'\n').replace(/\s+-\s+/g,'\n');
  let parts=t.split(/\n+/).map(v=>v.trim()).filter(Boolean);
  if(parts.length<=1 && t.length>180) parts=t.split(/(?<=[.!?])\s+/).map(v=>v.trim()).filter(Boolean);
  return parts.length?parts.map((v,i)=>`<div class=\"rule-item\"><b>${i+1}</b><span>${esc(v)}</span></div>`).join(''):'<div class=\"rule-item\"><b>1</b><span>Pastikan target dan jumlah pesanan sudah benar sebelum membeli.</span></div>';
};
const orderCode=id=>'WSO-'+String(id||'').replace(/-/g,'').slice(0,10).toUpperCase();
const depositCode=id=>'DEP-'+String(id||'').replace(/-/g,'').slice(0,10).toUpperCase();
const statusLabel=x=>({pending:'Menunggu',processing:'Diproses',success:'Sukses',completed:'Selesai',cancelled:'Dibatalkan',canceled:'Dibatalkan',failed:'Gagal',error:'Gagal',rejected:'Ditolak'})[String(x||'').toLowerCase()]||String(x||'Menunggu');

function appEl(){return document.getElementById('app');}

function showFatal(title,msg){
  const el=appEl();
  if(!el)return;
  el.innerHTML=`<main class="auth">
    <section class="card">
      <div class="brand"><i>W</i><b>${esc(setting('panel_name','WSID SMM PANEL'))}<small>${esc(setting('owner_name','Witama Store.ID'))}</small></b></div>
      <h1>${esc(title)}</h1>
      <p class="msg">${esc(msg)}</p>
      <button class="btn red wide" onclick="location.reload()">Muat Ulang</button>
      <p class="muted">Jika masih terjadi, kirim screenshot halaman ini.</p>
    </section>
  </main>`;
}

async function init(){
  const el=appEl();
  if(!el)return;

  el.innerHTML=`<main class="auth">
    <section class="card">
      <div class="brand"><i>W</i><b>${esc(setting('panel_name','WSID SMM PANEL'))}<small>${esc(setting('owner_name','Witama Store.ID'))}</small></b></div>
      <p class="muted">Memuat dashboard...</p>
    </section>
  </main>`;

  if(!window.sb){
    showFatal('Konfigurasi belum siap','Supabase belum terhubung. Periksa config.js.');
    return;
  }

  try{
    const q=await sb.auth.getSession();
    if(q.error)throw q.error;

    if(!q.data?.session){
      location.replace('login.html');
      return;
    }

    S.user=q.data.session.user;
    await load();
    await render();
    window.__WSID_BOOT_OK=true;
    clearTimeout(window.__WSID_BOOT_TIMER);
  }catch(e){
    console.error('Dashboard init error:',e);
    showFatal('Dashboard gagal dimuat',e?.message||'Terjadi kesalahan saat memuat dashboard.');
  }
}

async function load(){
  // Profile is useful but should never be able to blank the whole dashboard.
  try{
    const a=await sb.from('profiles').select('*').eq('id',S.user.id).maybeSingle();
    if(a.error)console.warn('Profile load:',a.error);
    S.profile=a.data||{full_name:S.user.user_metadata?.full_name||'Member',email:S.user.email};
  }catch(e){
    console.warn('Profile exception:',e);
    S.profile={full_name:S.user.user_metadata?.full_name||'Member',email:S.user.email};
  }

  try{
    const w=await sb.from('wallets').select('*').eq('user_id',S.user.id).maybeSingle();
    if(w.error)console.warn('Wallet load:',w.error);
    S.wallet=w.data||{balance:0};
  }catch(e){
    console.warn('Wallet exception:',e);
    S.wallet={balance:0};
  }

  try{
    const ps=await sb.from('panel_settings').select('key,value');
    if(!ps.error)(ps.data||[]).forEach(x=>S.settings[x.key]=x.value);
  }catch(e){console.warn('Settings load:',e);}

  try{
    let v=await sb.from('services')
      .select('*,categories(name)')
      .eq('is_active',true)
      .order('name');

    // Fallback if the categories relationship is not recognized by PostgREST.
    if(v.error){
      console.warn('Services relation query failed, using fallback:',v.error);
      v=await sb.from('services')
        .select('*')
        .eq('is_active',true)
        .order('name');
    }

    if(v.error)console.warn('Services load:',v.error);
    S.services=v.data||[];
  }catch(e){
    console.warn('Services exception:',e);
    S.services=[];
  }
}

function nav(p){S.page=p;render();}

function shell(c){
  return `<div class="shell">
    <header>
      <div class="brand"><i>W</i><b>${esc(setting('panel_name','WSID SMM PANEL'))}<small>${esc(setting('owner_name','Witama Store.ID'))}</small></b></div>
      <span class="user">${esc(S.profile?.full_name||'Member')} <button onclick="logout()">⋮</button></span>
    </header>
    <main>${c}</main>
    <nav>${[
      ['home','⌂','Beranda'],
      ['order','＋','Order'],
      ['orders','▣','Riwayat'],
      ['deposit','▤','Deposit'],
      ['profile','♙','Profil']
    ].map(x=>`<button class="${S.page===x[0]?'on':''}" onclick="nav('${x[0]}')">${x[1]}<small>${x[2]}</small></button>`).join('')}</nav>
  </div>`;
}

function home(){
  return `<section class="hero">
    <b>Selamat datang, ${esc(S.profile?.full_name||'Member')}!</b>
    <small>Semoga hari ini banyak orderan yang masuk! 🔥</small>
  </section>
  <div class="stats">
    <div><small>Total Saldo</small><b>${money(S.wallet?.balance)}</b></div>
    <div><small>Total Order</small><b>-</b></div>
    <div><small>Pending</small><b>-</b></div>
    <div><small>Total Profit</small><b>Rp 0</b></div>
  </div>
  <div class="banner"><b>${esc(setting('panel_name','WSID SMM PANEL'))}</b><span>Solusi terbaik untuk kebutuhan sosial media Anda</span><small>Cepat • Aman • Terpercaya</small></div>
  <h2>Layanan Populer</h2>
  <div class="grid2">${['TikTok','Instagram','YouTube','Facebook'].map(x=>`<button onclick="nav('order')"><b>${x}</b><small>Layanan ${x}</small></button>`).join('')}</div>
  <div class="balance"><span>Saldo Anda<br><b>${money(S.wallet?.balance)}</b></span><button class="btn red" onclick="nav('deposit')">Deposit</button></div>
  <div class="menus">${[
    ['order','🛒','Order','Pesan layanan sosial media'],
    ['orders','▣','Riwayat','Lihat semua riwayat'],
    ['deposit','▤','Deposit','Tambah saldo'],
    ['profile','♙','Profil','Kelola akun'],
  ].map(x=>`<button onclick="nav('${x[0]}')"><strong>${x[1]}</strong><span><b>${x[2]}</b><small>${x[3]}</small></span>›</button>`).join('')}</div>
`;
}

function order(){
  return `<div class="head"><h1>Pesan Layanan</h1><small>Pilih layanan yang kamu butuhkan.</small></div>
  <input id="search" placeholder="⌕ Cari layanan..." oninput="filter(this.value)">
  <div id="list" class="list">${cards(S.services)}</div>`;
}

function cards(a){
  return a.length
    ? a.map(s=>`<article class=\"service-card\">
      <i>${esc((s.name||'S')[0])}</i>
      <span><b>${esc(s.name)}</b><small>${money(s.sale_price)} per 1000</small></span>
      <button class=\"btn mini red buy-btn\" onclick=\"detail('${esc(s.id)}')\">Buy</button>
    </article>`).join('')
    : '<div class=\"empty\">Belum ada layanan. Admin perlu Sync Services.</div>';
}
window.filter=q=>{
  const el=document.getElementById('list');
  if(!el)return;
  const v=String(q||'').toLowerCase();
  el.innerHTML=cards(S.services.filter(x=>(x.name||'').toLowerCase().includes(v)));
};

window.detail=id=>{
  const s=S.services.find(x=>x.id===id);
  if(!s)return alert('Layanan tidak ditemukan.');

  appEl().innerHTML=shell(`<div class=\"head service-detail-head\"><button class=\"btn\" onclick=\"nav('order')\">← Kembali</button><div><h1>${esc(s.name)}</h1><small>${money(s.sale_price)} per 1000</small></div></div>
  <section class=\"card\">
    <h3>Peraturan Order</h3>
    <div class=\"rules-box\">${formatRules(s.description||'')}</div>
    <div class=\"order-form-box\">
      <label>Target<input id=\"target\" placeholder=\"Masukkan link / username target\"></label>
      <label>Jumlah<input id=\"qty\" type=\"number\" min=\"${s.min_qty}\" max=\"${s.max_qty}\" value=\"${s.min_qty}\"></label>
      <small class=\"muted\">Min ${Number(s.min_qty||0).toLocaleString('id-ID')} • Max ${Number(s.max_qty||0).toLocaleString('id-ID')}</small>
      <button class=\"btn red wide\" onclick=\"makeOrder('${esc(s.id)}')\">Buy Sekarang</button>
    </div>
  </section>`);
};
window.makeOrder=async id=>{
  const s=S.services.find(x=>x.id===id);
  if(!s)return alert('Layanan tidak ditemukan.');

  const target=document.getElementById('target')?.value.trim();
  const q=Number(document.getElementById('qty')?.value);
  const total=(Number(s.sale_price)/1000)*q;

  if(!target||q<s.min_qty||q>s.max_qty)return alert('Target/jumlah tidak valid.');
  if(Number(S.wallet?.balance||0)<total)return alert('Saldo tidak mencukupi.');

  try{
    const r=await sb.rpc('create_order',{p_service_id:id,p_target:target,p_quantity:q});
    if(r.error)throw r.error;

    const pr=await sb.rpc('submit_order',{p_order_id:r.data});
    if(pr.error)throw pr.error;
    const pj=pr.data||{};
    if(!pj.status)throw new Error(pj.msg||'Pengiriman layanan gagal.');

    alert('Pesanan berhasil dikirim.');
    await load();
    nav('orders');
  }catch(e){
    console.error('Order error:',e);
    alert(e?.message||'Order gagal.');
  }
};

async function orders(){
  try{
    const [o,d]=await Promise.all([
      sb.from('orders').select('*,services(name,category)').eq('user_id',S.user.id).order('created_at',{ascending:false}),
      sb.from('deposits').select('*').eq('user_id',S.user.id).order('created_at',{ascending:false})
    ]);
    if(o.error)throw o.error;
    if(d.error)throw d.error;
    const ordersRows=o.data||[], depositsRows=d.data||[];
    const items=[
      ...ordersRows.map(x=>({kind:'order',date:x.created_at,id:x.id,code:orderCode(x.id),name:x.services?.name||'Layanan',status:x.status,target:x.target,qty:x.quantity,total:x.sale_total})),
      ...depositsRows.map(x=>({kind:'deposit',date:x.created_at,id:x.id,code:depositCode(x.id),name:'Deposit Saldo',status:x.status,target:'Pengajuan deposit',qty:null,total:x.amount}))
    ].sort((a,b)=>new Date(b.date)-new Date(a.date));
    return `<div class=\"head order-head\"><div><h1>Riwayat</h1><small>Semua riwayat order dan deposit kamu.</small></div><span class=\"count-pill\">${items.length} Riwayat</span></div>
      <div class=\"order-list\">${items.map(o=>{
        const st=String(o.status||'pending').toLowerCase();
        return `<article class=\"order-card history-card\">
          <div class=\"order-icon\">${o.kind==='deposit'?'Rp':esc((o.name||'L')[0])}</div>
          <div class=\"order-main\">
            <div class=\"order-top\"><b>${esc(o.name)}</b><span class=\"status-badge status-${esc(st)}\">${esc(statusLabel(st))}</span></div>
            <small class=\"history-id\">ID: <b>${esc(o.code)}</b></small>
            <small class=\"order-target\">${esc(o.target||'')}</small>
            <div class=\"order-meta\">${o.kind==='order'?`<span>Jumlah <b>${Number(o.qty||0).toLocaleString('id-ID')}</b></span>`:''}<span>Total <b>${money(o.total)}</b></span><span>${new Date(o.date).toLocaleString('id-ID')}</span></div>
          </div>
        </article>`;
      }).join('')||'<div class=\"empty\">Belum ada riwayat.</div>'}</div>`;
  }catch(e){
    console.error('History error:',e);
    return `<div class=\"head\"><h1>Riwayat</h1><small>Semua riwayat order dan deposit kamu.</small></div><div class=\"card\"><p>Riwayat belum bisa dimuat.</p><small>${esc(e?.message||'Terjadi kesalahan.')}</small></div>`;
  }
}

function paymentLogo(type,label){
  const cls=String(type||'').toLowerCase();
  return `<button class="payment-logo ${cls}" onclick="showPayment('${esc(type)}')" aria-label="${esc(label)}"><span>${esc(label)}</span></button>`;
}
window.showPayment=type=>{
  const box=document.getElementById('payment-detail'); if(!box)return;
  const t=String(type||'').toLowerCase();
  if(t==='qris'){
    const img=setting('qris_image_url');
    box.innerHTML=img?`<div class="payment-detail-head"><b>QRIS</b><small>Scan QRIS untuk pembayaran.</small></div><img class="payment-qris" src="${esc(img)}" alt="QRIS"><small class="payment-note">Gunakan aplikasi pembayaran yang mendukung QRIS.</small>`:`<div class="empty">QRIS belum diatur oleh admin.</div>`;
  }else{
    const isGo=t==='gopay', name=isGo?setting('gopay_name',setting('owner_name','Witama Store.ID')):setting('dana_name',setting('owner_name','Witama Store.ID'));
    const num=isGo?setting('gopay_number','Nomor belum diatur'):setting('dana_number','Nomor belum diatur');
    box.innerHTML=`<div class="payment-detail-head"><b>${isGo?'GoPay':'DANA'}</b><small>${esc(name)}</small></div><div class="payment-number"><strong>${esc(num)}</strong><button class="btn" onclick="navigator.clipboard?.writeText(${JSON.stringify(num)});alert('Nomor disalin')">Salin</button></div><small class="payment-note">Transfer sesuai nominal yang kamu masukkan.</small>`;
  }
};
function deposit(){
  return `<div class="head"><h1>Deposit Saldo</h1><small>Pilih metode pembayaran, lalu kirim bukti pembayaran.</small></div>
  <section class="deposit-hero">
    <div class="deposit-title"><span class="deposit-icon">Rp</span><div><b>Tambah Saldo</b><small>Saldo masuk setelah admin melakukan ACC.</small></div></div>
    <div class="deposit-steps"><span><i>1</i> Pilih pembayaran</span><span><i>2</i> Upload bukti</span><span><i>3</i> Tunggu ACC admin</span></div>
  </section>
  <section class="deposit-card">
    <div class="section-label">Pembayaran</div>
    <div class="payment-logos">${paymentLogo('dana','DANA')}${paymentLogo('gopay','GoPay')}${paymentLogo('qris','QRIS')}</div>
    <div id="payment-detail" class="payment-detail"></div>
  </section>
  <section class="deposit-card">
    <div class="section-label">Nominal Deposit</div>
    <div class="amount-input-wrap"><span>Rp</span><input id="da" type="number" min="2000" step="1" inputmode="numeric" placeholder="Masukkan nominal"></div>
    <small class="deposit-min">Minimal deposit <b>Rp2.000</b></small>
  </section>
  <section class="deposit-card">
    <div class="section-label">Bukti Pembayaran</div>
    <div class="upload-box proof-upload" onclick="document.getElementById('df').click()"><span>↑</span><b>Pilih bukti transfer</b><small id="proof-name">JPG, PNG atau WEBP • maksimal 2MB</small><div id="proof-preview" class="proof-preview"></div><input id="df" type="file" accept="image/jpeg,image/png,image/webp" onchange="showProofName(this)"></div>
    <div class="deposit-note">Setelah mengirim bukti, status akan <b>Menunggu ACC Admin</b>. Silakan tunggu sampai admin memeriksa pengajuanmu.</div>
    <button class="btn red wide" onclick="sendDeposit()">Kirim Pengajuan Deposit</button>
  </section>`;
}
window.showProofName=input=>{const f=input?.files?.[0],el=document.getElementById('proof-name'),box=document.getElementById('proof-preview');if(box){if(window.__proofPreviewUrl)URL.revokeObjectURL(window.__proofPreviewUrl);box.innerHTML='';window.__proofPreviewUrl='';if(f){window.__proofPreviewUrl=URL.createObjectURL(f);box.innerHTML=`<img src="${window.__proofPreviewUrl}" class="proof-preview-img" alt="Preview bukti transfer"><small class="proof-preview-name">${esc(f.name)}</small>`;}}if(el)el.textContent=f?'Foto siap dikirim':'JPG, PNG atau WEBP • maksimal 2MB';};
window.sendDeposit=async()=>{
  try{
    const amount=Number(document.getElementById('da')?.value);
    const f=document.getElementById('df')?.files?.[0];
    if(!Number.isFinite(amount)||amount<2000||!f)return alert('Nominal minimal Rp2.000 dan bukti wajib diisi.');
    if(f.size>2*1024*1024)return alert('Ukuran bukti maksimal 2MB.');

    const path=`${S.user.id}/${crypto.randomUUID()}-${f.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
    const u=await sb.storage.from('deposit-proofs').upload(path,f);
    if(u.error)throw u.error;

    const r=await sb.from('deposits').insert({user_id:S.user.id,amount,proof_path:path}).select('id').single();
    if(r.error)throw r.error;

    alert('Pengajuan deposit berhasil. Silakan tunggu sampai admin melakukan ACC.');
    nav('home');
  }catch(e){
    console.error('Deposit error:',e);
    alert(e?.message||'Deposit gagal.');
  }
};

async function profile(){
  const devName=setting('developer_name','Witama Yuliananta');
  const devBio=setting('developer_bio','Developer dan pembuat WSID SMM PANEL. Website ini dikembangkan dan dikelola untuk kebutuhan Witama Store.ID.');
  const devLogo=setting('developer_logo_url','');
  const wa=setting('support_whatsapp',''), tg=setting('support_telegram','');
  return `<div class="head"><h1>Profil</h1></div>
  <section class="card center"><div class="avatar">${esc((S.profile?.full_name||'W')[0])}</div>
    <h2>${esc(S.profile?.full_name||'Member')}</h2><small>${esc(S.user.email||'')}</small>
    <p>Saldo <b>${money(S.wallet?.balance)}</b></p></section>
  <section class="developer-card">
    <div class="developer-title">${devLogo?`<img src="${esc(devLogo)}" alt="Developer">`:'<div class="developer-logo">W</div>'}<div><small>DEVELOPER WEBSITE</small><h2>${esc(devName)}</h2></div></div>
    <p>${esc(devBio)}</p>
    <div class="contact-logos">${wa?`<a class="contact-logo whatsapp" href="${esc(wa)}" target="_blank" rel="noopener" aria-label="WhatsApp"><span>WA</span></a>`:''}${tg?`<a class="contact-logo telegram" href="${esc(tg)}" target="_blank" rel="noopener" aria-label="Telegram"><span>TG</span></a>`:''}</div>
  </section>
  <div class="menus"><button onclick="logout()"><strong>↪</strong><span><b>Keluar</b><small>Keluar akun.</small></span>›</button></div>`;
}
async function render(){
  try{
    let c=S.page==='home'?home():
      S.page==='order'?order():
      S.page==='deposit'?deposit():
      S.page==='profile'?await profile():
      await orders();
    appEl().innerHTML=shell(c);
    if(S.page==='deposit') setTimeout(()=>showPayment('dana'),0);
  }catch(e){
    console.error('Render error:',e);
    showFatal('Tampilan gagal dimuat',e?.message||'Terjadi kesalahan saat menampilkan dashboard.');
  }
}

window.logout=async()=>{
  try{await sb.auth.signOut();}finally{location.replace('login.html');}
};

window.addEventListener('error',e=>{
  console.error('Unhandled error:',e.error||e.message);
  // Do not leave a blank black page if an unexpected frontend error occurs.
  if(appEl() && !appEl().innerHTML.trim()){
    showFatal('Terjadi kesalahan',e.message||'Kesalahan JavaScript.');
  }
});

init();
