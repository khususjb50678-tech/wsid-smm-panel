// Supabase Edge Function: wsid-api
// Public API for WSID SMM PANEL. It never exposes internal provider credentials.
import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
const C={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type,authorization','Access-Control-Allow-Methods':'POST,OPTIONS'};
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{...C,'Content-Type':'application/json'}});
const db=()=>createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
async function sha256(v:string){const b=new TextEncoder().encode(v);const h=await crypto.subtle.digest('SHA-256',b);return Array.from(new Uint8Array(h)).map(x=>x.toString(16).padStart(2,'0')).join('');}
async function provider(admin:any){const q=await admin.from('providers').select('*').eq('name','FAYUPEDIA').eq('is_active',true).single();if(q.error||!q.data?.api_id||!q.data?.api_key)throw new Error('Provider belum dikonfigurasi.');return q.data;}
async function callProvider(p:any,path:string,data:any={}){const f=new URLSearchParams({api_id:p.api_id,api_key:p.api_key});Object.entries(data).forEach(([k,v])=>f.set(k,String(v)));const base=String(p.base_url||'https://fayupedia.id/api').replace(/\/$/,'');const r=await fetch(`${base}/${path}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:f});try{return await r.json()}catch{return {status:false,msg:`Provider HTTP ${r.status}`}}}
async function authApi(admin:any,body:any){
  const api_id=String(body.api_id||'').trim(),api_key=String(body.api_key||'').trim();
  if(!api_id||!api_key)throw Object.assign(new Error('api_id dan api_key wajib diisi.'),{status:401});
  const hash=await sha256(api_key);
  const q=await admin.from('profiles').select('id,full_name,email,api_id,api_enabled').eq('api_id',api_id).eq('api_key_hash',hash).eq('api_enabled',true).maybeSingle();
  if(q.error)throw new Error(q.error.message);
  if(!q.data)throw Object.assign(new Error('API credentials tidak valid.'),{status:401});
  return q.data;
}
serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  if(req.method!=='POST')return out({status:false,msg:'Gunakan POST.'},405);
  try{
    const body=await req.json();
    const admin=db();
    const user=await authApi(admin,body);
    const action=String(body.action||body.task||'services').toLowerCase();

    if(action==='services'){
      const q=await admin.from('services').select('provider_service_id,name,type,category,sale_price,min_qty,max_qty,refill,description').eq('is_active',true).order('sort_order').order('name');
      if(q.error)throw new Error(q.error.message);
      return out({status:true,services:(q.data||[]).map((s:any)=>({service:s.provider_service_id,name:s.name,type:s.type,category:s.category,price:Number(s.sale_price||0),min:s.min_qty,max:s.max_qty,refill:!!s.refill,description:s.description||''}))});
    }

    const p=await provider(admin);
    if(action==='order'){
      const serviceId=String(body.service||'');const target=String(body.target||'');const quantity=Number(body.quantity||0);const comments=body.comments==null?null:String(body.comments);
      if(!serviceId||!target||!Number.isFinite(quantity)||quantity<=0)throw Object.assign(new Error('service, target, dan quantity wajib diisi.'),{status:400});
      const svc=await admin.from('services').select('id,type,provider_service_id').eq('provider_service_id',serviceId).eq('is_active',true).single();
      if(svc.error)throw Object.assign(new Error('Service tidak ditemukan.'),{status:404});
      const created=await admin.rpc('create_api_order',{p_user_id:user.id,p_service_id:svc.data.id,p_target:target,p_quantity:quantity,p_comments:comments});
      if(created.error)throw Object.assign(new Error(created.error.message),{status:400});
      const orderId=created.data;
      const payload:any={service:serviceId,target,quantity};if(comments)payload.comments=comments;
      const r=await callProvider(p,'order',payload);
      if(!r.status){
        const o=await admin.from('orders').select('sale_total').eq('id',orderId).single();
        await admin.from('orders').update({status:'failed',provider_status:'failed',error_message:r.msg||'Provider order failed',updated_at:new Date().toISOString()}).eq('id',orderId);
        if(o.data){const w=await admin.from('wallets').select('balance').eq('user_id',user.id).single();await admin.from('wallets').update({balance:Number(w.data?.balance||0)+Number(o.data.sale_total),updated_at:new Date().toISOString()}).eq('user_id',user.id);await admin.from('transactions').insert({user_id:user.id,type:'refund',amount:o.data.sale_total,reference_id:orderId,description:'Refund API provider gagal'});}
        return out({status:false,msg:r.msg||'Order provider gagal.'},400);
      }
      await admin.from('orders').update({provider_order_id:String(r.order||''),provider_status:'pending',status:'processing',updated_at:new Date().toISOString()}).eq('id',orderId);
      return out({status:true,order:r.order,msg:r.msg||'Order berhasil'});
    }

    if(action==='status'){
      const id=String(body.id||'');if(!id)throw Object.assign(new Error('id wajib diisi.'),{status:400});
      const own=await admin.from('orders').select('id,provider_order_id').eq('user_id',user.id).eq('provider_order_id',id).maybeSingle();
      if(!own.data)return out({status:false,msg:'Order tidak ditemukan.'},404);
      const r=await callProvider(p,'status',{id});
      if(r.order_status)await admin.from('orders').update({provider_status:String(r.order_status),status:String(r.order_status).toLowerCase(),updated_at:new Date().toISOString()}).eq('id',own.data.id);
      return out(r);
    }
    if(action==='refill'){
      const id=String(body.id||'');const own=await admin.from('orders').select('id').eq('user_id',user.id).eq('provider_order_id',id).maybeSingle();if(!own.data)return out({status:false,msg:'Order tidak ditemukan.'},404);return out(await callProvider(p,'refill',{id}));
    }
    if(action==='refill_status'){
      const id=String(body.id||'');const own=await admin.from('orders').select('id').eq('user_id',user.id).eq('provider_order_id',id).maybeSingle();if(!own.data)return out({status:false,msg:'Order tidak ditemukan.'},404);return out(await callProvider(p,'refill/status',{id}));
    }
    return out({status:false,msg:'Action tidak dikenal.'},400);
  }catch(e:any){return out({status:false,msg:e?.message||String(e)},e?.status||500)}
});
