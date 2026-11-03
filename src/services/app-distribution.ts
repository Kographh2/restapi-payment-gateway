import path from 'node:path';
import {readFile,realpath} from 'node:fs/promises';
import {createClient} from '@supabase/supabase-js';
import {z} from 'zod';
import {releaseManifest,releaseChannel,type ReleaseManifest,type PublicRelease,type ReleaseCatalog} from '@manji/validation/releases';
import type {Database} from './database';
import type {Config} from './config';
import {ApiError,ensure,hash,hmac,equal} from './security';

export interface ReleaseStorage {read(key:string):Promise<Buffer>;}
export class LocalReleaseStorage implements ReleaseStorage {
 constructor(private root:string){}
 async read(key:string){ensure(/^android\/(stable|beta)\/[0-9]+\/[a-f0-9]{64}\/(app\.apk|screenshots\/[0-9]+\.(png|jpg))$/.test(key),404,'NOT_FOUND');const root=await realpath(this.root),target=await realpath(path.join(root,key));ensure(target.startsWith(root+path.sep),404,'NOT_FOUND');return readFile(target);}
}
export class SupabaseReleaseStorage implements ReleaseStorage {
 private client;constructor(c:Config,private bucket:string){this.client=createClient(c.NEXT_PUBLIC_SUPABASE_URL!,c.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});}
 async read(key:string){const bucket=await this.client.storage.getBucket(this.bucket);ensure(!bucket.error&&bucket.data&&!bucket.data.public,503,'PRIVATE_ARTIFACT_STORAGE_REQUIRED');const result=await this.client.storage.from(this.bucket).download(key);ensure(!result.error&&result.data&&result.data.size<=83_886_080,503,'ARTIFACT_UNAVAILABLE');return Buffer.from(await result.data.arrayBuffer());}
}
const ticketSchema=z.object({id:z.string().uuid(),sha256:z.string().regex(/^[a-f0-9]{64}$/),expires:z.number().int(),purpose:z.literal('apk')}).strict();
export class AppDistribution {
 constructor(private db:Database,private storage:ReleaseStorage,private settings:{profile:'production'|'test';signers:Set<string>;ticketSecret:string},private now=()=>Date.now()){}
 private approved(raw:unknown){const parsed=releaseManifest.safeParse(raw);ensure(parsed.success,503,'INVALID_RELEASE_METADATA');const m=parsed.data;ensure(m.profile===this.settings.profile&&this.settings.signers.has(m.signer_sha256),503,'UNAPPROVED_RELEASE_SIGNER');ensure(Date.parse(m.released_at)<=this.now()+60000,503,'INVALID_RELEASE_DATE');return m;}
 private public(m:ReleaseManifest):PublicRelease {return {id:m.id,application_id:m.application_id,channel:m.channel,version_code:m.version_code,version_name:m.version_name,released_at:m.released_at,min_sdk:m.min_sdk,target_sdk:m.target_sdk,size_bytes:m.size_bytes,sha256:m.sha256,signer_sha256:m.signer_sha256,notes:m.notes,download_path:`/v1/app/releases/${m.id}/download`,screenshots:m.screenshots.map((s,i)=>({url:`/v1/app/releases/${m.id}/screenshots/${i}`,caption:s.caption,width:s.width,height:s.height}))};}
 async catalog(channel:'stable'|'beta',historyLimit=30):Promise<ReleaseCatalog>{const rows=await this.db.rpc<unknown[]>('app_release_command',{p_command:'list',p_data:{channel,profile:this.settings.profile}});const releases=rows.map(r=>this.approved(r)).sort((a,b)=>b.version_code-a.version_code).map(m=>this.public(m));return {available:releases.length>0,channel,distribution_environment:this.settings.profile,release:releases[0]??null,history:releases.slice(0,historyLimit)};}
 private async find(id:string){z.string().uuid().parse(id);const raw=await this.db.rpc('app_release_command',{p_command:'get',p_data:{id,profile:this.settings.profile}});ensure(raw,404,'APP_RELEASE_UNAVAILABLE','Rilis tidak tersedia atau telah ditarik');return this.approved(raw);}
 async link(id:string){const r=await this.find(id),payload=Buffer.from(JSON.stringify({id:r.id,sha256:r.sha256,expires:Math.floor(this.now()/1000)+120,purpose:'apk'})).toString('base64url');return `/v1/app/releases/${r.id}/file?ticket=${payload}.${hmac(this.settings.ticketSecret,payload)}`;}
 private async verified(key:string,size:number,sha:string){const bytes=await this.storage.read(key);ensure(bytes.length===size&&equal(hash(bytes),sha),503,'ARTIFACT_INTEGRITY_FAILED','Integritas berkas gagal diperiksa; unduhan diblokir');return bytes;}
 async file(id:string,ticket:string,range:string|null){
  ensure(ticket.length<=1024,401,'INVALID_DOWNLOAD_TICKET');const parts=ticket.split('.');ensure(parts.length===2&&equal(hmac(this.settings.ticketSecret,parts[0]),parts[1]),401,'INVALID_DOWNLOAD_TICKET');let raw:unknown;try{raw=JSON.parse(Buffer.from(parts[0],'base64url').toString());}catch{throw new ApiError(401,'INVALID_DOWNLOAD_TICKET','Tautan unduhan tidak valid');}
  const parsed=ticketSchema.safeParse(raw);ensure(parsed.success&&parsed.data.id===id&&parsed.data.expires>Math.floor(this.now()/1000)&&parsed.data.expires<=Math.floor(this.now()/1000)+125,401,'EXPIRED_DOWNLOAD_TICKET','Tautan unduhan berakhir. Mulai unduhan kembali.');const r=await this.find(id);ensure(parsed.data.sha256===r.sha256,401,'INVALID_DOWNLOAD_TICKET');
  const bytes=await this.verified(r.apk_key,r.size_bytes,r.sha256),headers:Record<string,string>={'content-type':'application/vnd.android.package-archive','content-disposition':`attachment; filename="manji-gateway-${r.version_name}-${r.channel}.apk"`,'accept-ranges':'bytes','x-checksum-sha256':r.sha256,'etag':'"'+r.sha256+'"','referrer-policy':'no-referrer','x-robots-tag':'noindex','cache-control':'private, no-store','x-content-type-options':'nosniff'};
  if(range){const match=/^bytes=(\d+)-(\d*)$/.exec(range);if(!match)return new Response(null,{status:416,headers:{'content-range':`bytes */${bytes.length}`}});const start=Number(match[1]),end=match[2]?Number(match[2]):bytes.length-1;if(!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start>end||end>=bytes.length)return new Response(null,{status:416,headers:{'content-range':`bytes */${bytes.length}`}});headers['content-range']=`bytes ${start}-${end}/${bytes.length}`;headers['content-length']=String(end-start+1);return new Response(new Uint8Array(bytes.subarray(start,end+1)),{status:206,headers});}
  headers['content-length']=String(bytes.length);return new Response(new Uint8Array(bytes),{headers});
 }
 async screenshot(id:string,index:number){const r=await this.find(id),s=r.screenshots[index];ensure(s,404,'NOT_FOUND');return new Response(new Uint8Array(await this.verified(s.key,s.size_bytes,s.sha256)),{headers:{'content-type':s.mime,'cache-control':'private, max-age=60','x-content-type-options':'nosniff'}});}
}
export function appDistribution(c:Config,db:Database){
 const signers=new Set((process.env.APP_RELEASE_CERT_SHA256??'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean)),ticketSecret=process.env.APP_DOWNLOAD_TOKEN_SECRET??'';
 ensure(signers.size&&[...signers].every(s=>/^[a-f0-9]{64}$/.test(s))&&ticketSecret.length>=32,503,'APP_DISTRIBUTION_NOT_CONFIGURED','Distribusi aplikasi belum dikonfigurasi');
 const test=process.env.APP_RELEASE_TEST_MODE==='1';ensure(!test||c.PAYMENT_ENV==='sandbox'&&c.STORE_DRIVER==='pglite'&&['localhost','127.0.0.1'].includes(new URL(c.APP_BASE_URL).hostname),503,'TEST_DISTRIBUTION_FORBIDDEN');
 if(test){ensure(process.env.APP_RELEASE_LOCAL_DIR,503,'APP_DISTRIBUTION_NOT_CONFIGURED');return new AppDistribution(db,new LocalReleaseStorage(process.env.APP_RELEASE_LOCAL_DIR),{profile:'test',signers,ticketSecret});}
 ensure(c.STORE_DRIVER==='supabase',503,'PRIVATE_ARTIFACT_STORAGE_REQUIRED');ensure(!process.env.APP_RELEASE_BUCKET||process.env.APP_RELEASE_BUCKET==='manji-app-releases',503,'PRIVATE_ARTIFACT_STORAGE_REQUIRED');ensure([c.APP_BASE_URL,c.API_BASE_URL,c.NEXT_PUBLIC_SUPABASE_URL??''].every(v=>v.startsWith('https:')),503,'HTTPS_REQUIRED');return new AppDistribution(db,new SupabaseReleaseStorage(c,'manji-app-releases'),{profile:'production',signers,ticketSecret});
}
export async function appDistributionRoute(req:Request,c:Config,db:Database,provided?:AppDistribution){
 const url=new URL(req.url),route=url.pathname.replace(/^\/api\/v1/,'/v1');ensure(req.method==='GET',405,'METHOD_NOT_ALLOWED');
 const service=provided??appDistribution(c,db);if(process.env.APP_RELEASE_TEST_MODE==='1')ensure(['localhost','127.0.0.1'].includes(url.hostname),404,'NOT_FOUND');
 await db.rpc('account_command',{p_actor:null,p_session:null,p_command:'rate',p_data:{key:route.endsWith('/version')?'app-version':'app-artifacts',limit:route.endsWith('/version')?1200:120}});
 if(route==='/v1/app/version'){const query=z.object({channel:releaseChannel.default('stable'),history_limit:z.coerce.number().int().min(0).max(30).default(30)}).strict().parse(Object.fromEntries(url.searchParams));return Response.json(await service.catalog(query.channel,query.history_limit));}
 if(route==='/v1/app/latest/download'){const query=z.object({channel:releaseChannel.default('stable')}).strict().parse(Object.fromEntries(url.searchParams)),catalog=await service.catalog(query.channel);ensure(catalog.release,503,'APP_RELEASE_UNAVAILABLE','Rilis Android resmi belum diterbitkan');return new Response(null,{status:307,headers:{location:await service.link(catalog.release.id),'referrer-policy':'no-referrer'}});}
 const match=route.match(/^\/v1\/app\/releases\/([a-f0-9-]+)\/(download|file|screenshots\/([0-7]))$/i);ensure(match,404,'NOT_FOUND');
 if(match[2]==='download'){ensure(!url.search,400,'VALIDATION_ERROR');return new Response(null,{status:307,headers:{location:await service.link(match[1]),'referrer-policy':'no-referrer'}});}
 if(match[2]==='file'){const q=z.object({ticket:z.string().min(40).max(1024)}).strict().parse(Object.fromEntries(url.searchParams));return service.file(match[1],q.ticket,req.headers.get('range'));}
 ensure(!url.search,400,'VALIDATION_ERROR');return service.screenshot(match[1],Number(match[3]));
}
