import {lookup} from 'node:dns/promises';
import {request} from 'node:https';
import {isIP} from 'node:net';
import type {Database} from './database';
import type {Config} from './config';
import {decrypt,ensure,hmac} from './security';
export function publicAddress(address:string){
  if(isIP(address)===4){const [a,b]=address.split('.').map(Number);return !(a===0||a===10||a===127||a>=224||a===169&&b===254||a===172&&b>=16&&b<=31||a===192&&b===168||a===100&&b>=64&&b<=127||a===198&&(b===18||b===19)||a===192&&b===0);}
  return isIP(address)===6&&/^[23][0-9a-f]{3}:/i.test(address)&&!/^2001:db8:/i.test(address)&&!address.includes('.');
}
export function validateEndpoint(value:string,c:Config){const u=new URL(value),hosts=c.WEBHOOK_ALLOWED_HOSTS.split(',').map(x=>x.trim()).filter(Boolean);ensure(u.protocol==='https:'&&!u.username&&!u.password&&!u.hash&&(!u.port||u.port==='443')&&hosts.includes(u.hostname)&&!isIP(u.hostname),400,'UNSAFE_ENDPOINT','HTTPS dan host yang disetujui operator wajib digunakan');return u;}
export async function sendWebhook(url:string,body:string,headers:Record<string,string>,c:Config):Promise<{status:number;body:string}>{
  const u=validateEndpoint(url,c),addresses=await lookup(u.hostname,{all:true});ensure(addresses.length&&addresses.every(x=>publicAddress(x.address)),400,'UNSAFE_ADDRESS');const pin=addresses[0];
  return new Promise((resolve,reject)=>{const req=request(u,{method:'POST',headers:{...headers,'content-type':'application/json','content-length':Buffer.byteLength(body)},lookup:(_host,_options,cb)=>cb(null,pin.address,pin.family),timeout:8000},res=>{let size=0;const chunks:Buffer[]=[];res.on('data',(b:Buffer)=>{size+=b.length;if(size>8192){res.destroy();reject(new Error('response limit'));}else chunks.push(b);});res.on('end',()=>resolve({status:res.statusCode??0,body:Buffer.concat(chunks).toString()}));res.on('error',reject);});req.on('timeout',()=>req.destroy(new Error('timeout')));req.on('error',reject);req.end(body);});
}
type Task={delivery:{id:string;event_type:string;environment:string;payload:Record<string,unknown>;lease_token:string};endpoint:{url:string;secret_encrypted:string;challenge:string}};
export async function drainOutbox(db:Database,c:Config,send=sendWebhook){let processed=0;for(let i=0;i<20;i++){
  const task=await db.rpc<Task|null>('worker_command',{p_command:'outbox.claim',p_data:{}});if(!task)break;const timestamp=Math.floor(Date.now()/1000).toString(),body=JSON.stringify({id:task.delivery.id,type:task.delivery.event_type,environment:task.delivery.environment,data:task.delivery.payload});let ok=false,status=0;
  try{const response=await send(task.endpoint.url,body,{'x-delivery-id':task.delivery.id,'x-webhook-timestamp':timestamp,'x-webhook-signature':hmac(decrypt(task.endpoint.secret_encrypted,c.APP_ENCRYPTION_KEY),timestamp+'.'+body)},c);status=response.status;ok=status>=200&&status<300;if(ok&&task.delivery.event_type==='endpoint.verification')ok=JSON.parse(response.body).challenge===task.endpoint.challenge;}catch{ok=false;}
  await db.rpc('worker_command',{p_command:'outbox.finish',p_data:{id:task.delivery.id,lease_token:task.delivery.lease_token,ok,status}});processed++;
 }await db.rpc('worker_command',{p_command:'retention',p_data:{}});return {processed};}
