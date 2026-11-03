'use client';
import {createClient} from '@supabase/supabase-js';
import {api} from './client';
export async function subscribePayments(onChange:()=>void,onState:(state:string)=>void){
  const config=await api<{enabled:boolean;url?:string;anon_key?:string;access_token?:string;schema?:string;table?:string;merchant_id?:string}>('/v1/realtime/config');
  if(!config.enabled){onState('Sandbox · pembaruan berkala');const timer=setInterval(onChange,5000);return ()=>clearInterval(timer);}
  const client=createClient(config.url!,config.anon_key!,{auth:{persistSession:false,autoRefreshToken:false}});await client.realtime.setAuth(config.access_token!);
  const channel=client.channel('merchant:'+config.merchant_id).on('postgres_changes',{event:'*',schema:config.schema!,table:config.table!,filter:'merchant_id=eq.'+config.merchant_id},()=>onChange()).subscribe(status=>onState(status==='SUBSCRIBED'?'Realtime tersambung':'Realtime terputus · coba sambungkan ulang'));
  const timer=setInterval(async()=>{try{const next=await api<typeof config>('/v1/realtime/config');await client.realtime.setAuth(next.access_token!);}catch{onState('Sesi realtime perlu diperbarui');}},240000);
  return ()=>{clearInterval(timer);void client.removeChannel(channel);void client.realtime.disconnect();};
}
