import {randomUUID} from 'node:crypto';
import {z,ZodError} from 'zod';
import * as input from '@manji/validation';
import {config,type Config} from './config';
import {database,type Database} from './database';
import {authenticate,adminOnly,merchantId,userOnly,type Principal} from './auth';
import {Identity,type SessionTokens} from './identity';
import {ApiError,cookieValue,decrypt,encrypt,ensure,equal,hash,hmac,secret} from './security';
import {MockProviderAdapter,OfficialProviderAdapter,commitVerified} from './providers';
import {drainOutbox,validateEndpoint} from './outbox';
import {validateImage} from './images';
import {appDistributionRoute,type AppDistribution} from './app-distribution';
const json=(data:unknown,status=200)=>Response.json(data,{status,headers:{'cache-control':'no-store'}});
const logSegments=new Set('v1 health auth register login verify refresh reset-password resend-verification me merchants merchant logout password sessions device enroll redeem devices status events payments cancel qr-sources image profile api-keys rotate revoke webhooks endpoints test dashboard privacy export signals sandbox confirm provider webhook official mailbox realtime config internal outbox admin overview applications review accounts configuration enrollment-credential merchant-applications'.split(' '));
const safeOperation=(path:string)=>path.split('/').map(segment=>!segment||logSegments.has(segment)?segment:':id').join('/');
type Dependencies={c:Config;db:Database;distribution?:AppDistribution};
function cookie(name:string,value:string,c:Config,maxAge:number){return `${name}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAge}${c.APP_BASE_URL.startsWith('https:')?'; Secure':''}`;}
function tokenResponse(tokens:SessionTokens,c:Config,req:Request){
  const mobile=req.headers.get('x-client-type')==='android';const response=json({access_token:tokens.access_token,...mobile?{refresh_token:tokens.refresh_token}:{},user_id:tokens.user_id,session_id:tokens.session_id,expires_at:tokens.expires_at,expires_in:Math.max(0,tokens.expires_at-Math.floor(Date.now()/1000)),environment:c.PAYMENT_ENV});
  response.headers.append('set-cookie',cookie('manji_access',tokens.access_token,c,3600));response.headers.append('set-cookie',cookie('manji_refresh',encrypt(tokens.refresh_token,c.APP_ENCRYPTION_KEY),c,30*86400));return response;
}
async function readBody(req:Request){ensure(Number(req.headers.get('content-length')??0)<=1000000,413,'BODY_TOO_LARGE');const reader=req.body?.getReader();if(!reader)return '';let length=0;const chunks:Uint8Array[]=[];while(true){const next=await reader.read();if(next.done)break;length+=next.value.length;if(length>1000000){await reader.cancel();throw new ApiError(413,'BODY_TOO_LARGE','Permintaan terlalu besar');}chunks.push(next.value);}return Buffer.concat(chunks).toString('utf8');}
const plain=(data:unknown)=>{ensure(data!==null&&typeof data==='object'&&!Array.isArray(data));return data as Record<string,unknown>;};
function decryptResult(data:unknown,c:Config,kind?:'key'|'device'|'challenge'|'webhook'){
  if(data&&typeof data==='object'&&'secret_already_issued'in data)throw new ApiError(409,'SECRET_ALREADY_ISSUED','Secret sudah diterbitkan sekali. Jika respons pertama hilang, cabut/rotasi credential atau mulai enrollment baru.');
  if(!data||typeof data!=='object'||!('secret_ciphertext'in data))return data;const record={...data} as Record<string,unknown>;const token=decrypt(String(record.secret_ciphertext),c.APP_ENCRYPTION_KEY);delete record.secret_ciphertext;
  if(kind==='device')record.device_token=token;else if(kind==='challenge')record.challenge=token;else if(kind==='webhook')record.signing_secret=token;else record.api_key=token;return record;
}
function secretFields(c:Config,prefix:'key'|'device'|'challenge'|'webhook'){
  const id=randomUUID(),value=prefix==='key'?`${c.PAYMENT_ENV==='sandbox'?'mg_sbx':'mg_live'}_${id}.${secret()}`:prefix==='device'?`md_${id}.${secret()}`:secret();
  return {id,secret_hash:hash(value),secret_ciphertext:encrypt(value,c.APP_ENCRYPTION_KEY),public_id:prefix==='key'?value.split('.')[0]:undefined};
}
export async function handle(req:Request,deps?:Dependencies){
  const requestId=randomUUID(),started=Date.now();let c:Config|undefined,db:Database|undefined,p:Principal|undefined,operation='unknown',response:Response;let errorCode='';
  try{c=deps?.c??config();db=deps?.db??await database(c);response=await route(req,c,db,(principal,op)=>{p=principal;operation=op;},deps?.distribution);}
  catch(error){const e=error instanceof ApiError?error:error instanceof ZodError||error instanceof SyntaxError?new ApiError(400,'VALIDATION_ERROR','Periksa isian dan format permintaan'):new ApiError(503,'SERVICE_UNAVAILABLE','Layanan belum tersedia. Periksa konfigurasi server.');errorCode=e.code;response=json({error:{code:e.code,message:e.message,request_id:requestId}},e.status);if(e.status===429)response.headers.set('retry-after','60');}
  response.headers.set('x-request-id',requestId);response.headers.set('cache-control',response.headers.get('content-type')==='application/vnd.android.package-archive'?'private, no-store, no-transform':'no-store');response.headers.set('x-content-type-options','nosniff');
  if(db){try{await db.rpc('worker_command',{p_command:'request.log',p_data:{merchant_id:p?.merchant??null,actor_id:p?.actor??null,credential_id:p?.subject??null,request_id:requestId,operation,method:req.method,status_code:response.status,duration_ms:Date.now()-started,code:errorCode||'REQUEST_REJECTED'}});}catch{/* Do not log bodies, credentials or internal database messages. */}}
  return response;
}
async function route(req:Request,c:Config,db:Database,trace:(p:Principal|undefined,operation:string)=>void,distribution?:AppDistribution):Promise<Response>{
  const url=new URL(req.url),path=url.pathname.replace(/^\/api\/v1(?=\/|$)/,'/v1').replace(/\/$/,''),method=req.method;
  ensure(['GET','POST','DELETE'].includes(method),405,'METHOD_NOT_ALLOWED');trace(undefined,safeOperation(path));
  if(method!=='GET'&&!req.headers.has('authorization')&&(req.headers.has('origin')||req.headers.has('cookie')))ensure(req.headers.get('origin')===new URL(c.APP_BASE_URL).origin,403,'ORIGIN_DENIED','Origin tidak diizinkan');
  if(path.startsWith('/v1/app/'))return appDistributionRoute(req,c,db,distribution);
  if((path==='/health'||path==='/v1/health')&&method==='GET'){await db.rpc('account_command',{p_actor:null,p_session:null,p_command:'public.configuration',p_data:{}});return json({ok:true,product:'MANJI Gateway',environment:c.PAYMENT_ENV,provider_enabled:false,auth:c.STORE_DRIVER==='supabase'?'Supabase Auth':'sandbox_local',realtime:c.STORE_DRIVER==='supabase'?'supabase':'sandbox_polling'});}
  const raw=method!=='GET'?await readBody(req):'';
  if(path==='/v1/internal/outbox'&&method==='POST'){
    ensure(c.OUTBOX_CRON_SECRET&&equal(req.headers.get('authorization')??'','Bearer '+c.OUTBOX_CRON_SECRET),401,'UNAUTHENTICATED');z.object({}).strict().parse(raw?JSON.parse(raw):{});return json(await drainOutbox(db,c));
  }
  if(path==='/v1/provider/webhook/official'&&method==='POST'){await new OfficialProviderAdapter().verify();throw new Error('unreachable');}
  if(path==='/v1/sandbox/provider/webhook'&&method==='POST'){
    ensure(c.PAYMENT_ENV==='sandbox',404,'NOT_FOUND');await db.rpc('account_command',{p_actor:null,p_session:null,p_command:'rate',p_data:{key:'sandbox-callback',limit:60}});
    const event=await new MockProviderAdapter(c).verify(raw,req.headers.get('x-mock-signature'),Date.now());return json(await commitVerified(db,event,c));
  }
  const body=raw?JSON.parse(raw):{},identity=new Identity(db,c);
  if(path.startsWith('/v1/auth/')&&['/v1/auth/register','/v1/auth/login','/v1/auth/verify','/v1/auth/refresh','/v1/auth/reset-password','/v1/auth/resend-verification'].includes(path)){
    ensure(method==='POST',405,'METHOD_NOT_ALLOWED');await db.rpc('account_command',{p_actor:null,p_session:null,p_command:'rate',p_data:{key:'auth:'+path,limit:20}});
    if(path.endsWith('/register')){const x=input.register.parse(body);return json(await identity.register(x.email,x.password,x.display_name),202);}
    if(path.endsWith('/login')){const x=input.login.parse(body);return tokenResponse(await identity.login(x.email,x.password,x.device_name),c,req);}
    if(path.endsWith('/verify')){const x=z.object({token_hash:z.string().min(16).max(512),type:z.enum(['email','recovery'])}).strict().parse(body);return tokenResponse(await identity.verify(x.token_hash,x.type),c,req);}
    if(path.endsWith('/refresh')){
      const x=z.object({refresh_token:z.string().min(16).max(4096).optional()}).strict().parse(body);let refresh=x.refresh_token;const stored=cookieValue(req,'manji_refresh');if(!refresh&&stored){try{refresh=decrypt(stored,c.APP_ENCRYPTION_KEY);}catch{throw new ApiError(401,'SESSION_EXPIRED','Masuk kembali');}}ensure(refresh,401,'SESSION_EXPIRED','Masuk kembali');return tokenResponse(await identity.refresh(refresh),c,req);
    }
    const x=z.object({email:z.string().email().max(254)}).strict().parse(body);return json(path.endsWith('/resend-verification')?await identity.resend(x.email):await identity.reset(x.email),202);
  }
  const p=await authenticate(req,c,db);trace(p,safeOperation(path));
  await db.rpc('account_command',{p_actor:null,p_session:null,p_command:'rate',p_data:{key:hash(p.actor+':'+(p.subject??p.session)),limit:p.kind==='device'?60:120}});
  const account=(command:string,data:unknown={},mutation=false)=>{userOnly(p);return db.rpc(mutation?'account_mutation':'account_command',{p_actor:p.actor,p_session:p.session,p_command:command,p_data:data,...mutation?{p_idempotency:req.headers.get('idempotency-key'),p_fingerprint:hash(JSON.stringify({path,body}))}:{}});};
  const merchant=(command:string,data:unknown={},mutation=false)=>db.rpc('merchant_command',{p_actor:p.actor,p_session:p.session,p_merchant:merchantId(p),p_kind:p.kind,p_subject:p.subject,p_command:command,p_data:{...plain(data),environment:c.PAYMENT_ENV},p_idempotency:mutation?req.headers.get('idempotency-key'):null,p_fingerprint:mutation?hash(JSON.stringify({merchant:p.merchant,path,body})):null});
  if(path==='/v1/auth/me'&&method==='GET')return json({...await identity.me(userOnly(p)),current_session_id:p.session});
  if(path==='/v1/auth/merchants'&&method==='GET')return json((await identity.me(userOnly(p))).merchants);
  if(path==='/v1/auth/merchant'&&method==='POST'){
    const x=z.object({merchant_id:input.uuid}).strict().parse(body),me=await identity.me(userOnly(p));ensure(me.merchants.some(m=>m.merchant_id===x.merchant_id),404,'NOT_FOUND');const response=json({ok:true});response.headers.append('set-cookie',cookie('manji_merchant',x.merchant_id,c,30*86400));return response;
  }
  if(path==='/v1/auth/logout'&&method==='POST'){
    z.object({}).strict().parse(body);await identity.logout(userOnly(p));const response=json({ok:true});for(const name of ['manji_access','manji_refresh','manji_merchant'])response.headers.append('set-cookie',cookie(name,'',c,0));return response;
  }
  if(path==='/v1/auth/password'&&method==='POST'){const x=z.object({password:input.password}).strict().parse(body);return json(await identity.changePassword(userOnly(p),x.password));}
  if(path==='/v1/auth/sessions'&&method==='GET')return json(await account('sessions.list'));
  const session=path.match(/^\/v1\/auth\/sessions\/([a-f0-9-]+)$/i);if(session&&method==='DELETE'){input.uuid.parse(session[1]);return json(await account('sessions.revoke',{id:session[1]},true));}
  if(path==='/v1/merchant-applications'&&method==='POST')return json(await account('applications.submit',input.application.parse(body),true),201);
  if(path==='/v1/admin/overview'&&method==='GET'){adminOnly(p);return json(await account('admin.overview'));}
  const review=path.match(/^\/v1\/admin\/applications\/([a-f0-9-]+)\/review$/i);if(review&&method==='POST'){
    adminOnly(p);const x=z.object({action:z.enum(['approve','reject']),note:z.string().trim().min(3).max(500)}).strict().parse(body);return json(await account('admin.application.review',{...x,id:input.uuid.parse(review[1])},true));
  }
  const status=path.match(/^\/v1\/admin\/(accounts|merchants)\/([a-f0-9-]+)\/status$/i);if(status&&method==='POST'){
    adminOnly(p);const x=z.object({status:z.enum(['ACTIVE','SUSPENDED'])}).strict().parse(body);return json(await account(status[1]==='accounts'?'admin.account.status':'admin.merchant.status',{...x,id:input.uuid.parse(status[2])},true));
  }
  if(path==='/v1/admin/configuration'&&method==='POST'){adminOnly(p);return json(await account('admin.configuration',input.sourceConfig.parse(body),true));}
  const adminRevoke=path.match(/^\/v1\/admin\/(api-keys|devices)\/([a-f0-9-]+)\/revoke$/i);if(adminRevoke&&method==='POST'){adminOnly(p);z.object({}).strict().parse(body);return json(await account(adminRevoke[1]==='api-keys'?'admin.key.revoke':'admin.device.revoke',{id:input.uuid.parse(adminRevoke[2])},true));}
  const adminEnrollment=path.match(/^\/v1\/admin\/merchants\/([a-f0-9-]+)\/enrollment-credential$/i);if(adminEnrollment&&method==='POST'){adminOnly(p);z.object({}).strict().parse(body);return json(decryptResult(await account('admin.enrollment.create',{...secretFields(c,'key'),merchant_id:input.uuid.parse(adminEnrollment[1])},true),c,'key'),201);}
  if(path==='/v1/sandbox/mailbox'&&method==='GET'){
    adminOnly(p);ensure(db.local&&c.PAYMENT_ENV==='sandbox',404,'NOT_FOUND');const mail=await db.local.query<{id:string;email:string;type:string;token_encrypted:string;created_at:string;used_at:string|null}>('select m.id,u.email,m.type,m.token_encrypted,m.created_at,m.used_at from gateway_sandbox.mail m join auth.users u on u.id=m.user_id order by created_at desc limit 50');
    return json(mail.rows.map(({token_encrypted,...m})=>({...m,confirmation_link:'/auth/confirm#token_hash='+encodeURIComponent(decrypt(token_encrypted,c.APP_ENCRYPTION_KEY))+'&type='+m.type})));
  }
  if(path==='/v1/realtime/config'&&method==='GET'){
    userOnly(p);await merchant('merchant.profile');return json(c.STORE_DRIVER==='supabase'?{enabled:true,url:c.NEXT_PUBLIC_SUPABASE_URL,anon_key:c.NEXT_PUBLIC_SUPABASE_ANON_KEY,access_token:p.user!.access_token,schema:'manji_gateway',table:'payment_requests',merchant_id:p.merchant}:{enabled:false,reason:'sandbox_local'});
  }
  if(path==='/v1/merchant/profile'&&method==='GET')return json(await merchant('merchant.profile'));
  if(path==='/v1/dashboard'&&method==='GET'){userOnly(p);return json(await merchant('dashboard'));}
  if(path==='/v1/merchant/devices'&&method==='GET')return json(await merchant('devices.list'));
  if(path==='/v1/devices/status'&&method==='GET')return json(await merchant('devices.status'));
  if(path==='/v1/payments'&&method==='GET')return json(await merchant('payments.list',input.pagination.parse(Object.fromEntries(url.searchParams))));
  if(path==='/v1/payments'&&method==='POST'){
    const x=input.payment.parse(body);if(x.qr_mode==='PROVIDER_DYNAMIC_QRIS')await new OfficialProviderAdapter().createDynamic();return json(await merchant('payments.create',x,true),201);
  }
  const payment=path.match(/^\/v1\/payments\/([a-f0-9-]+)(?:\/(status|cancel))?$/i);
  if(payment){const id=input.uuid.parse(payment[1]);if(method==='GET'&&payment[2]!=='cancel')return json(await merchant(payment[2]==='status'?'payments.status':'payments.get',{id}));if(method==='POST'&&payment[2]==='cancel'){z.object({}).strict().parse(body);return json(await merchant('payments.cancel',{id},true));}}
  if(path==='/v1/qr-sources'&&method==='POST'){
    userOnly(p);const x=z.object({mime:z.enum(['image/png','image/jpeg']),bytes_base64:z.string().max(950000),ownership_confirmed:z.literal(true)}).strict().parse(body),bytes=validateImage(x.bytes_base64,x.mime);return json(await merchant('qr.create',{...x,id:randomUUID(),sha256:hash(bytes)},true),201);
  }
  const image=path.match(/^\/v1\/qr-sources\/([a-f0-9-]+)\/image$/i);if(image&&method==='GET'){
    const result=await merchant('qr.image',{id:input.uuid.parse(image[1])}) as {mime:string;bytes_base64:string};return new Response(Buffer.from(result.bytes_base64,'base64'),{headers:{'content-type':result.mime,'content-disposition':'inline','cache-control':'no-store'}});
  }
  if(path==='/v1/auth/device/enroll'&&method==='POST'){
    const x=input.enroll.parse(body);return json(decryptResult(await merchant('devices.enroll',{...x,...secretFields(c,'challenge')},true),c,'challenge'));
  }
  if(path==='/v1/auth/device/redeem'&&method==='POST'){
    const x=z.object({challenge_id:input.uuid,challenge:z.string().length(64)}).strict().parse(body);return json(decryptResult(await merchant('devices.redeem',{challenge_id:x.challenge_id,challenge_hash:hash(x.challenge),...secretFields(c,'device')},true),c,'device'));
  }
  const device=path.match(/^\/v1\/merchant\/devices\/([a-f0-9-]+)\/(revoke|rotate)$/i);if(device&&method==='POST'){
    userOnly(p);z.object({}).strict().parse(body);const fields=secretFields(c,'device');return json(decryptResult(await merchant(device[2]==='revoke'?'devices.revoke':'devices.rotate',{...fields,credential_id:fields.id,id:input.uuid.parse(device[1])},true),c,'device'));
  }
  if(path==='/v1/devices/events'&&method==='POST')return json(await merchant('signals.create',input.signal.parse(body),true));
  if(path==='/v1/merchant/api-keys'&&method==='GET'){userOnly(p);return json(await merchant('keys.list'));}
  if(path==='/v1/merchant/api-keys'&&method==='POST'){
    userOnly(p);return json(decryptResult(await merchant('keys.create',{...input.apiKey.parse(body),...secretFields(c,'key')},true),c,'key'),201);
  }
  const apiKey=path.match(/^\/v1\/merchant\/api-keys\/([a-f0-9-]+)(?:\/(rotate))?$/i);if(apiKey){
    userOnly(p);const id=input.uuid.parse(apiKey[1]);if(method==='DELETE'&&!apiKey[2])return json(await merchant('keys.revoke',{id},true));if(method==='POST'&&apiKey[2]){z.object({}).strict().parse(body);const fields=secretFields(c,'key');return json(decryptResult(await merchant('keys.rotate',{...fields,id,new_id:fields.id},true),c,'key'));}
  }
  if(path==='/v1/webhooks/endpoints'&&method==='GET')return json(await merchant('webhooks.list'));
  if(path==='/v1/webhooks/endpoints'&&method==='POST'){
    const x=input.endpoint.parse(body);validateEndpoint(x.url,c);return json(decryptResult(await merchant('webhooks.create',{...x,...secretFields(c,'webhook'),challenge:secret()},true),c,'webhook'),201);
  }
  const endpoint=path.match(/^\/v1\/webhooks\/endpoints\/([a-f0-9-]+)(?:\/(test|rotate))?$/i);if(endpoint){
    const id=input.uuid.parse(endpoint[1]);if(method==='DELETE'&&!endpoint[2])return json(await merchant('webhooks.revoke',{id},true));if(method==='POST'&&endpoint[2]){z.object({}).strict().parse(body);return json(decryptResult(await merchant(endpoint[2]==='test'?'webhooks.test':'webhooks.rotate',{...secretFields(c,'webhook'),id,challenge:secret()},true),c,'webhook'));}
  }
  if(path==='/v1/privacy/export'&&method==='GET'){userOnly(p);return json(await merchant('dashboard'));}
  if(path==='/v1/privacy/signals'&&method==='DELETE'){userOnly(p);z.object({}).strict().parse(body);return json(await merchant('privacy.delete_signals',{},true));}
  if(path==='/v1/sandbox/confirm'&&method==='POST'){
    userOnly(p);ensure(c.PAYMENT_ENV==='sandbox'&&c.MOCK_PROVIDER_SECRET,404,'NOT_FOUND');const x=z.object({payment_id:input.uuid}).strict().parse(body),payment=await merchant('payments.get',{id:x.payment_id}) as {id:string;merchant_id:string;amount_idr:number};
    ensure(/^[\w.-]{8,128}$/.test(req.headers.get('idempotency-key')??''),400,'IDEMPOTENCY_REQUIRED');
    // Derive stable UUIDs from the request idempotency key so UI retries cannot create additional settlements.
    const stable=(suffix:string)=>{const h=hash(p.actor+':'+payment.id+':'+req.headers.get('idempotency-key')+suffix);return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;};
    const event={event_id:stable('event'),merchant_id:payment.merchant_id,payment_id:payment.id,transaction_id:stable('tx'),amount_idr:payment.amount_idr,currency:'IDR',event_type:'settlement',environment:'sandbox',timestamp:Math.floor(Date.now()/300000)*300},eventRaw=JSON.stringify(event),verified=await new MockProviderAdapter(c).verify(eventRaw,hmac(c.MOCK_PROVIDER_SECRET,eventRaw),Date.now());return json(await commitVerified(db,verified,c));
  }
  throw new ApiError(404,'NOT_FOUND','Endpoint tidak ditemukan');
}
