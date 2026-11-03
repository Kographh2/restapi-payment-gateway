import assert from 'node:assert/strict';
import {test} from 'node:test';
import {validateEnvironment} from '../src/services/config';
import {SupabaseDatabase} from '../src/services/database';
import {handle} from '../src/services/http';
import {register} from '../src/instrumentation';

const c=validateEnvironment({PAYMENT_ENV:'production',PROVIDER_MODE:'official',STORE_DRIVER:'supabase',APP_BASE_URL:'https://fixture.example',API_BASE_URL:'https://fixture.example',WEBSITE_URL:'https://fixture.example',APP_ENCRYPTION_KEY:'ab'.repeat(32),NEXT_PUBLIC_SUPABASE_URL:'https://fixture.supabase.co',NEXT_PUBLIC_SUPABASE_ANON_KEY:'public-fixture-'.repeat(3),SUPABASE_SERVICE_ROLE_KEY:'private-fixture-'.repeat(3),OUTBOX_CRON_SECRET:'cron-fixture-'.repeat(4)});
const leak='NEVER_LOG_TOKEN_EMAIL_PASSWORD_OR_SQL_ROW';
type Scenario={rpcError?:{code:string;status:number;message?:string};network?:boolean;registrationOpen?:boolean;authStatus?:number;authCode?:string;delay?:boolean};
async function fixture<T>(scenario:Scenario,run:(db:SupabaseDatabase,calls:{kind:string;command?:string;schema?:string|null}[],logs:string[])=>Promise<T>){
 const previousFetch=globalThis.fetch,previousError=console.error,previousWarn=console.warn;
 const logs:string[]=[],calls:{kind:string;command?:string;schema?:string|null}[]=[];
 console.error=(line:unknown)=>{logs.push(String(line));};console.warn=(line:unknown)=>{logs.push(String(line));};
 globalThis.fetch=async(input,init)=>{
  const url=new URL(typeof input==='string'||input instanceof URL?input.toString():input.url);
  if(url.hostname!=='fixture.supabase.co')throw Error('Unexpected non-fixture request');
  const headers=new Headers(init?.headers),body=JSON.parse(String(init?.body??'{}'));
  if(url.pathname.startsWith('/rest/v1/rpc/')){
   assert.equal(headers.get('apikey'),c.SUPABASE_SERVICE_ROLE_KEY);
   calls.push({kind:'rpc',command:body.p_command,schema:headers.get('content-profile')});
   if(scenario.delay)await new Promise(resolve=>setTimeout(resolve,3));
   if(scenario.network)throw Error('fetch failed '+leak);
   if(scenario.rpcError)return Response.json({code:scenario.rpcError.code,message:scenario.rpcError.message??leak,details:leak,hint:leak},{status:scenario.rpcError.status});
   return Response.json(body.p_command==='public.configuration'?{registration_open:scenario.registrationOpen!==false}:{ok:true});
  }
  if(url.pathname==='/auth/v1/signup'){
   assert.equal(headers.get('apikey'),c.NEXT_PUBLIC_SUPABASE_ANON_KEY);
   calls.push({kind:'signup'});
   if(scenario.authStatus)return Response.json({code:scenario.authCode??'unexpected_failure',msg:leak},{status:scenario.authStatus});
   return Response.json({id:'20000000-0000-4000-8000-000000000002',aud:'authenticated',role:'authenticated',email:'fixture@example.invalid',app_metadata:{provider:'email'},user_metadata:{display_name:'Fixture'},identities:[],created_at:'2026-11-03T00:00:00Z'});
  }
  throw Error('Unexpected fixture path');
 };
 try{return await run(new SupabaseDatabase(c),calls,logs);}finally{globalThis.fetch=previousFetch;console.error=previousError;console.warn=previousWarn;}
}
const request=(path='/v1/auth/register',body:unknown={email:'fixture@example.invalid',password:leak,display_name:'Fixture'})=>new Request('https://fixture.example'+path,{method:'POST',headers:{origin:'https://fixture.example','content-type':'application/json'},body:JSON.stringify(body)});

test('production official mode permits registration through the real Supabase SDK and custom-schema RPC transport',async()=>{
 for(const path of ['/v1/auth/register','/api/v1/auth/register'])await fixture({},async(db,calls,logs)=>{
  const response=await handle(request(path),{c,db});assert.equal(response.status,202);
  assert.deepEqual(await response.json(),{accepted:true,email_verification_required:true,delivery:'supabase_email',role:'PENDING'});
  assert.deepEqual(calls.slice(0,3).map(call=>call.command??call.kind),['rate','public.configuration','signup']);
  assert.ok(calls.filter(call=>call.kind==='rpc').every(call=>call.schema==='manji_gateway'));
  assert.ok(!calls.some(call=>call.command?.includes('provider')));assert.deepEqual(logs,[]);
 });
});

test('PGRST106 reproduces the live 503 before signup and logs the exact subsystem without credential contents',async()=>{
 await fixture({rpcError:{code:'PGRST106',status:406}},async(db,calls,logs)=>{
  const response=await handle(request(),{c,db}),body=await response.json();
  assert.equal(response.status,503);assert.equal(body.error.code,'DATABASE_UNAVAILABLE');
  assert.ok(!calls.some(call=>call.kind==='signup'));
  const records=logs.map(line=>JSON.parse(line));
  assert.ok(records.some(row=>row.subsystem==='database.supabase'&&row.failure==='schema_not_exposed'&&row.upstream_code==='PGRST106'&&row.upstream_status===406&&row.command==='rate'&&row.request_id===body.error.request_id));
  assert.ok(!logs.join('').includes(leak));assert.ok(!logs.join('').includes(c.SUPABASE_SERVICE_ROLE_KEY!));assert.ok(!JSON.stringify(body).includes('PGRST106'));
 });
});

test('missing migrations, permissions, rejected server credentials and transport failures remain failures with specific diagnostics',async()=>{
 for(const [code,status,failure]of [['PGRST202',404,'rpc_missing_or_schema_cache_stale'],['42P01',400,'migration_missing'],['42501',403,'database_permission_denied'],['PGRST301',401,'server_credentials_rejected']] as const){
  await fixture({rpcError:{code,status}},async(db,_calls,logs)=>{assert.equal((await handle(request(),{c,db})).status,503);assert.ok(logs.some(line=>JSON.parse(line).failure===failure));});
 }
 await fixture({network:true},async(db,_calls,logs)=>{assert.equal((await handle(request(),{c,db})).status,503);assert.ok(logs.some(line=>JSON.parse(line).failure==='database_transport_unavailable'));assert.ok(!logs.join('').includes(leak));});
});

test('closed registration, SQL role/session exceptions and rate limits are never bypassed',async()=>{
 await fixture({registrationOpen:false},async(db,calls)=>{assert.equal((await handle(request(),{c,db})).status,403);assert.ok(!calls.some(call=>call.kind==='signup'));});
 for(const [message,status]of [['FORBIDDEN',403],['UNAUTHENTICATED',401],['RATE_LIMITED',429]] as const)await fixture({rpcError:{code:'P0001',status:400,message}},async(db,calls)=>{assert.equal((await handle(request(),{c,db})).status,status);assert.ok(!calls.some(call=>call.kind==='signup'));});
});

test('Supabase Auth infrastructure failure is distinguished from database RPC failure and password validation',async()=>{
 await fixture({authStatus:500},async(db,_calls,logs)=>{const response=await handle(request(),{c,db});assert.equal(response.status,503);assert.equal((await response.json()).error.code,'REGISTRATION_UNAVAILABLE');assert.ok(logs.some(line=>JSON.parse(line).subsystem==='auth.supabase'));assert.ok(!logs.join('').includes(leak));});
 await fixture({authStatus:422,authCode:'weak_password'},async(db)=>{assert.equal((await handle(request(),{c,db})).status,400);});
 await fixture({authStatus:429,authCode:'over_email_send_rate_limit'},async(db)=>{assert.equal((await handle(request(),{c,db})).status,429);});
});

test('successful database health does not require official provider onboarding',async()=>{
 await fixture({},async(db)=>{const response=await handle(new Request('https://fixture.example/health'),{c,db});assert.equal(response.status,200);assert.equal((await response.json()).provider_enabled,false);});
});

test('concurrent requests retain separate diagnostic request IDs',async()=>{
 await fixture({rpcError:{code:'PGRST106',status:406},delay:true},async(db,_calls,logs)=>{
  const responses=await Promise.all([handle(request(),{c,db}),handle(request(),{c,db})]);
  const ids=await Promise.all(responses.map(async r=>(await r.json()).error.request_id));assert.notEqual(ids[0],ids[1]);
  for(const id of ids)assert.ok(logs.some(line=>JSON.parse(line).request_id===id));
 });
});

test('provider startup capability is informational once per process and never blocks auth',async()=>{
 const previousEnv=process.env,previousInfo=console.info,logs:string[]=[];
 try{process.env={...process.env,...c,NEXT_RUNTIME:'nodejs'} as NodeJS.ProcessEnv;console.info=(line:unknown)=>{logs.push(String(line));};await register();await register();assert.equal(logs.length,1);assert.equal(JSON.parse(logs[0]).subsystem,'payments.provider');}
 finally{process.env=previousEnv;console.info=previousInfo;}
});
