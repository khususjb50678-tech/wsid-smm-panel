const C=window.WSID_CONFIG||{};
const S={page:'home',user:null,profile:null,wallet:{balance:0},services:[],settings:{}};
const setting=(k,f='')=>S.settings?.[k]??f;

const money=n=>new Intl.NumberFormat('id-ID',{
  style:'currency',currency:'IDR',maximumFractionDigits:0
}).format(Number(n||0));

const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[c]));

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
      ['orders','▣','Pesanan'],
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
  <h2>Provider Populer</h2>
  <div class="grid2">${['TikTok','Instagram','YouTube','Facebook'].map(x=>`<button onclick="nav('order')"><b>${x}</b><small>Layanan ${x}</small></button>`).join('')}</div>
  <div class="balance"><span>Saldo Anda<br><b>${money(S.wallet?.balance)}</b></span><button class="btn red" onclick="nav('deposit')">Deposit</button></div>
  <div class="menus">${[
    ['order','🛒','Order','Pesan layanan sosial media'],
    ['orders','▣','Pesanan','Lihat status pesanan'],
    ['deposit','▤','Deposit','Tambah saldo'],
    ['profile','♙','Profil','Kelola akun'],
    ['docs','▤','Docs API','Dokumentasi integrasi']
  ].map(x=>`<button onclick="nav('${x[0]}')"><strong>${x[1]}</strong><span><b>${x[2]}</b><small>${x[3]}</small></span>›</button>`).join('')}</div>
  <div class="notice">⚠️ <span><b>Informasi Penting</b><small>Pastikan saldo provider mencukupi untuk proses order.</small></span></div>`;
}

function order(){
  return `<div class="head"><h1>Pesan Layanan</h1><small>Pilih layanan yang kamu butuhkan.</small></div>
  <input id="search" placeholder="⌕ Cari layanan..." oninput="filter(this.value)">
  <div id="list" class="list">${cards(S.services)}</div>`;
}

function cards(a){
  return a.length
    ? a.map(s=>`<article>
      <i>${esc((s.name||'S')[0])}</i>
      <span><b>${esc(s.name)}</b><small>${esc(s.description||'')}</small><strong>${money(s.sale_price)}</strong></span>
      <button class="btn mini" onclick="detail('${esc(s.id)}')">＋</button>
    </article>`).join('')
    : '<div class="empty">Belum ada layanan. Admin perlu Sync Services.</div>';
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

  appEl().innerHTML=shell(`<div class="head"><button onclick="nav('order')">←</button><h1>${esc(s.name)}</h1></div>
  <section class="card">
    <p>${esc(s.description||'')}</p>
    <p>Harga: <b>${money(s.sale_price)}</b> per 1000</p>
    <label>Target<input id="target"></label>
    <label>Jumlah<input id="qty" type="number" min="${s.min_qty}" max="${s.max_qty}" value="${s.min_qty}"></label>
    <button class="btn red wide" onclick="makeOrder('${esc(s.id)}')">Buat Pesanan</button>
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

    const sess=(await sb.auth.getSession()).data?.session;
    if(!sess)throw new Error('Session login sudah berakhir. Silakan login kembali.');

    const pr=await fetch(`${C.SUPABASE_URL}/functions/v1/provider-order`,{
      method:'POST',
      headers:{
        Authorization:`Bearer ${sess.access_token}`,
        'Content-Type':'application/json'
      },
      body:JSON.stringify({order_id:r.data})
    });

    let pj={};
    try{pj=await pr.json();}catch(_){}

    if(!pr.ok||!pj.status)throw new Error(pj.msg||`Order provider gagal (${pr.status}).`);

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
    const r=await sb.from('orders')
      .select('*,services(name)')
      .eq('user_id',S.user.id)
      .order('created_at',{ascending:false});

    if(r.error)throw r.error;

    return `<div class="head"><h1>Pesanan Saya</h1></div>
      <div class="list">${(r.data||[]).map(o=>`<article>
        <span><b>${esc(o.services?.name||'Layanan')}</b><small>${esc(o.target)}</small></span>
        <span><b>${money(o.sale_total)}</b><small class="status">${esc(o.status)}</small></span>
      </article>`).join('')||'<div class="empty">Belum ada pesanan.</div>'}</div>`;
  }catch(e){
    console.error('Orders error:',e);
    return `<div class="head"><h1>Pesanan Saya</h1></div><div class="card"><p>Pesanan belum bisa dimuat.</p><small>${esc(e?.message||'Terjadi kesalahan.')}</small></div>`;
  }
}

function deposit(){
  return `<div class="head"><h1>Deposit Saldo</h1><small>Transfer manual lalu upload bukti.</small></div>
  <section class="card"><div class="pay">
    <b>Bayar ke DANA</b><span>${esc(setting('dana_name',setting('owner_name','Witama Store.ID')))}</span>
    <strong>${esc(setting('dana_number','Nomor belum diatur'))}</strong>
    <button class="btn" onclick="navigator.clipboard?.writeText(setting('dana_number',''))">Salin</button>
    ${setting('qris_image_url')?`<img src="${esc(setting('qris_image_url'))}" alt="QRIS">`:''}
  </div>
  <label>Nominal<input id="da" type="number" min="1000" placeholder="50000"></label>
  <label>Bukti<input id="df" type="file" accept="image/*"></label>
  <button class="btn red wide" onclick="sendDeposit()">Ajukan Deposit</button></section>`;
}

window.sendDeposit=async()=>{
  try{
    const amount=Number(document.getElementById('da')?.value);
    const f=document.getElementById('df')?.files?.[0];
    if(amount<1000||!f)return alert('Nominal dan bukti wajib diisi.');

    const path=`${S.user.id}/${crypto.randomUUID()}-${f.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
    const u=await sb.storage.from('deposit-proofs').upload(path,f);
    if(u.error)throw u.error;

    const r=await sb.from('deposits').insert({user_id:S.user.id,amount,proof_path:path});
    if(r.error)throw r.error;

    alert('Deposit menunggu ACC admin.');
    nav('home');
  }catch(e){
    console.error('Deposit error:',e);
    alert(e?.message||'Deposit gagal.');
  }
};

async function profile(){
  const api= S.profile?.api_id ? `<section class="card"><h3>API Saya</h3><p><b>API ID</b></p><pre>${esc(S.profile.api_id)}</pre><p><b>API Key</b></p><pre>${S.profile.api_key_last4?`••••••••${esc(S.profile.api_key_last4)}`:'Belum dibuat'}</pre><small class="muted">Untuk keamanan, API key lengkap hanya ditampilkan saat admin membuat/reset key.</small></section>` : `<section class="card"><b>API belum dibuat</b><p class="muted">Hubungi admin untuk membuat API ID dan API Key.</p></section>`;
  return `<div class="head"><h1>Profil</h1></div>
  <section class="card center"><div class="avatar">${esc((S.profile?.full_name||'W')[0])}</div>
    <h2>${esc(S.profile?.full_name||'Member')}</h2><small>${esc(S.user.email||'')}</small>
    <p>Saldo <b>${money(S.wallet?.balance)}</b></p></section>${api}
  <div class="menus"><button onclick="nav('docs')"><strong>▤</strong><span><b>Docs API</b><small>Dokumentasi API WSID.</small></span>›</button><button onclick="logout()"><strong>↪</strong><span><b>Keluar</b><small>Keluar akun.</small></span>›</button></div>`;
}

function docs(){
  const endpoint=`${C.SUPABASE_URL}/functions/v1/wsid-api`;
  return `<div class="head"><h1>Docs API</h1><small>${esc(setting('panel_name','WSID SMM PANEL'))}</small></div>
  <section class="card"><p>API publik untuk integrasi layanan panel.</p><h3>Endpoint</h3><pre>${esc(endpoint)}</pre><h3>Autentikasi</h3><pre>api_id=YOUR_API_ID
api_key=YOUR_API_KEY</pre><h3>Services</h3><pre>POST ${esc(endpoint)}
{"api_id":"YOUR_API_ID","api_key":"YOUR_API_KEY","action":"services"}</pre><h3>Order</h3><pre>POST ${esc(endpoint)}
{"api_id":"YOUR_API_ID","api_key":"YOUR_API_KEY","action":"order","service":"SERVICE_ID","target":"@username","quantity":1000}</pre><h3>Status</h3><pre>POST ${esc(endpoint)}
{"api_id":"YOUR_API_ID","api_key":"YOUR_API_KEY","action":"status","id":"ORDER_ID"}</pre><h3>Refill</h3><pre>POST ${esc(endpoint)}
{"api_id":"YOUR_API_ID","api_key":"YOUR_API_KEY","action":"refill","id":"ORDER_ID"}</pre><h3>Refill Status</h3><pre>POST ${esc(endpoint)}
{"api_id":"YOUR_API_ID","api_key":"YOUR_API_KEY","action":"refill_status","id":"ORDER_ID"}</pre></section>`;
}

async function render(){
  try{
    let c=S.page==='home'?home():
      S.page==='order'?order():
      S.page==='deposit'?deposit():
      S.page==='profile'?await profile():
      S.page==='docs'?docs():
      await orders();
    appEl().innerHTML=shell(c);
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
