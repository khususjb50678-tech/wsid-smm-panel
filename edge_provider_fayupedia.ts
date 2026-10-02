// Supabase Edge Function: provider-fayupedia
// Credentials are read from public.providers by the server. Do NOT put them in GitHub/config.js.
import {serve} from 'https://deno.land/std@0.224.0/http/server.ts';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';

const C={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,content-type'};
const out=(x:any,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{...C,'Content-Type':'application/json'}});

async function provider(db:any){
  const q=await db.from('providers').select('*').eq('name','FAYUPEDIA').eq('is_active',true).maybeSingle();
  if(q.error)throw new Error(q.error.message);
  if(!q.data?.api_id||!q.data?.api_key)throw new Error('API ID / API Key provider belum diisi di Admin > Provider.');
  return q.data;
}

async function api(p:any,path:string,data:any={}){
  const base=String(p.base_url||'https://fayupedia.id/api').replace(/\/$/,'');
  const f=new URLSearchParams({api_id:p.api_id,api_key:p.api_key});
  Object.entries(data).forEach(([k,v])=>f.set(k,String(v)));
  const r=await fetch(`${base}/${path}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:f});
  let j:any;try{j=await r.json();}catch{j={status:false,msg:`Provider HTTP ${r.status}`};}
  return j;
}

serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:C});
  try{
    const auth=req.headers.get('Authorization')||'';
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}});
    const {data:{user}}=await db.auth.getUser();
    if(!user)return out({status:false,msg:'Unauthorized'},401);
    const p=await db.from('profiles').select('role').eq('id',user.id).single();
    if(p.data?.role!=='admin')return out({status:false,msg:'Admin only'},403);
    const b=await req.json();
    const cfg=await provider(db);

    if(b.action==='provider_settings'){
      return out({status:true,name:cfg.name,base_url:cfg.base_url,api_id:cfg.api_id||'',has_api_key:!!cfg.api_key,markup_type:cfg.default_markup_type,markup_value:cfg.default_markup_value,is_active:cfg.is_active});
    }
    if(b.action==='balance')return out(await api(cfg,'balance'));
    if(b.action==='services')return out(await api(cfg,'services'));
    if(b.action==='status')return out(await api(cfg,'status',{id:b.id}));
    if(b.action==='refill')return out(await api(cfg,'refill',{id:b.id}));
    if(b.action==='refill_status')return out(await api(cfg,'refill/status',{id:b.id}));
    if(b.action==='order')return out(await api(cfg,'order',b.order||{}));
    if(b.action==='sync_services'){
      const r=await api(cfg,'services');
      if(!r.status)return out(r);
      for(const s of r.services||[]){
        const catName=s.category||'Lainnya';
        const slug=catName.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')||'lainnya';
        const cat=await db.from('categories').upsert({name:catName,slug},{onConflict:'name'}).select('id').single();
        const old=await db.from('services').select('markup_type,markup_value').eq('provider_service_id',String(s.id)).maybeSingle();
        const mt=old.data?.markup_type||cfg.default_markup_type||'percent';
        const mv=Number(old.data?.markup_value ?? cfg.default_markup_value ?? 0);
        const price=Number(s.price||0);
        const sale=mt==='fixed'?price+mv:price*(1+mv/100);
        await db.from('services').upsert({provider_service_id:String(s.id),name:s.name,type:s.type||'default',category_id:cat.data?.id,category:catName,provider_price:price,markup_type:mt,markup_value:mv,sale_price:sale,min_qty:Number(s.min||1),max_qty:Number(s.max||1),refill:Boolean(s.refill),description:s.description||'',is_active:true},{onConflict:'provider_service_id'});
      }
      return out({status:true,msg:'Services synced',count:(r.services||[]).length});
    }
    return out({status:false,msg:'Unknown action'},400);
  }catch(e){return out({status:false,msg:String(e)},500)}
});
