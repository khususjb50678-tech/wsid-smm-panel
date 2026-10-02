const m=document.getElementById('m');
const say=x=>{if(m)m.textContent=x};

if(!window.sb){
  say('Supabase belum dikonfigurasi. Periksa config.js.');
}

document.getElementById('f')?.addEventListener('submit',async ev=>{
  ev.preventDefault();
  if(!window.sb)return say('Supabase belum dikonfigurasi.');

  const button=ev.currentTarget.querySelector('button[type="submit"],button');
  if(button)button.disabled=true;
  say('Memproses...');

  try{
    const email=document.getElementById('e').value.trim();
    const password=document.getElementById('p').value;

    if(location.pathname.endsWith('register.html')){
      const name=document.getElementById('n').value.trim();
      if(!name)return say('Nama wajib diisi.');

      const r=await sb.auth.signUp({
        email,
        password,
        options:{data:{full_name:name}}
      });

      if(r.error)throw r.error;

      if(r.data?.session){
        say('Berhasil! Membuka dashboard...');
        location.replace('index.html');
        return;
      }

      // This only happens when Supabase still requires email confirmation.
      say('Akun berhasil dibuat. Jika Confirm Email masih aktif, konfirmasi email terlebih dahulu lalu login.');
      return;
    }

    const r=await sb.auth.signInWithPassword({email,password});
    if(r.error)throw r.error;

    say('Login berhasil. Membuka dashboard...');
    location.replace('index.html');
  }catch(e){
    console.error(e);
    say(e?.message||'Terjadi kesalahan. Coba lagi.');
  }finally{
    if(button)button.disabled=false;
  }
});
