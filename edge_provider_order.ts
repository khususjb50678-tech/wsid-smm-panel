// Supabase Edge Function: provider-order
// Reads provider credentials from the database; never expose them to the browser.
import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
const C={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,content-type'};
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{...C,'Content-Type':'application/json'}});
async function api(p:any,path:string,data:any){
  const f=new URLSearchParams({api_id:p.api_id||'',api_key:p.api_key||''});
  Object.entries(data).forEach(([k,v])=>f.set(k,String(v)));
  const base=String(p.base_url||'https://fayupedia.id/api').replace(/\/$/,'');
  const r=await fetch(`${base}/${path}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:f});
  try{return await r.json();}catch{return {status:false,msg:`Koneksi HTTP ${r.status}`};}
}
serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  try{
    const auth=req.headers.get('Authorization')||'';
    const client=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}});
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const {data:{user}}=await client.auth.getUser();
    if(!user)return out({status:false,msg:'Unauthorized'},401);
    const {order_id}=await req.json();
    const q=await admin.from('orders').select('*,services(provider_service_id,type)').eq('id',order_id).eq('user_id',user.id).single();
    if(q.error)return out({status:false,msg:q.error.message},404);
    const o=q.data;
    if(o.provider_order_id)return out({status:true,msg:'Already submitted',order:o.provider_order_id});
    const p=await admin.from('providers').select('*').eq('name','FAYUPEDIA').eq('is_active',true).single();
    if(p.error||!p.data?.api_id||!p.data?.api_key)return out({status:false,msg:'Koneksi layanan belum dikonfigurasi di Admin > Koneksi.'},500);
    const payload:any={service:o.services.provider_service_id,target:o.target,quantity:o.quantity};
    if(o.comments)payload.comments=o.comments;
    const r=await api(p.data,'order',payload);
    if(!r.status){
      await admin.from('orders').update({status:'failed',provider_status:'failed',error_message:r.msg||'Pengiriman layanan gagal',updated_at:new Date().toISOString()}).eq('id',o.id);
      const w=await admin.from('wallets').select('balance').eq('user_id',user.id).single();
      await admin.from('wallets').update({balance:Number(w.data?.balance||0)+Number(o.sale_total),updated_at:new Date().toISOString()}).eq('user_id',user.id);
      await admin.from('transactions').insert({user_id:user.id,type:'refund',amount:o.sale_total,reference_id:o.id,description:'Refund pesanan gagal'});
      return out({status:false,msg:r.msg||'Pengiriman layanan gagal'},400);
    }
    await admin.from('orders').update({provider_order_id:String(r.order||''),provider_status:'pending',status:'processing',updated_at:new Date().toISOString()}).eq('id',o.id);
    return out({status:true,order:r.order,msg:r.msg||'Order berhasil dikirim'});
  }catch(e){return out({status:false,msg:String(e)},500)}
});
