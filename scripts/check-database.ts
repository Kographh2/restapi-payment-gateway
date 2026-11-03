import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import nextEnv from '@next/env';
import {validateEnvironment,ConfigurationError} from '../src/services/config';
import {SupabaseDatabase,schema} from '../src/services/database';
import {DependencyError,logDiagnostic,requestDiagnostics} from '../src/services/diagnostics';

await requestDiagnostics.run({request_id:randomUUID(),operation:'/diagnostics/database',method:'CLI'},async()=>{
 try{
  const args=process.argv.slice(2);
  if(args.some(arg=>!['--production','--endpoint'].includes(arg)))throw Error('Invalid arguments');
  const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
  nextEnv.loadEnvConfig(root,false,{info:()=>{},error:()=>{throw Error('Environment loading failed');}});
  const c=validateEnvironment(process.env);
  if(c.STORE_DRIVER!=='supabase'||args.includes('--production')&&c.PAYMENT_ENV!=='production'){
   console.error(JSON.stringify({event:'database_check',ok:false,failure:'requires_configured_supabase_environment'}));process.exitCode=1;return;
  }
  // Read-only RPC: no signup, rate mutation, merchant data or migration execution.
  const db=new SupabaseDatabase(c);
  const settings=await db.rpc<{registration_open:boolean}>('account_command',{p_actor:null,p_session:null,p_command:'public.configuration',p_data:{}});
  if(!settings||typeof settings.registration_open!=='boolean'){
   logDiagnostic('error',{event:'dependency_failure',subsystem:'database.supabase',failure:'registration_configuration_missing',rpc:'account_command',command:'public.configuration'});
   throw new DependencyError('database.supabase','registration_configuration_missing');
  }
  console.log(JSON.stringify({event:'database_check',ok:true,schema,registration_open:settings.registration_open,provider_verification_enabled:false}));
  if(args.includes('--endpoint')){
   // The registration probe is intentionally invalid. It cannot create an account
   // or email, but the endpoint still exercises its real database rate-limit RPC.
   for(const [pathname,method]of [['/health','GET'],['/v1/auth/register','POST']] as const){
    const response=await fetch(new URL(pathname,c.APP_BASE_URL),{method,headers:method==='POST'?{'content-type':'application/json',origin:c.APP_BASE_URL}:{},...method==='POST'?{body:'{}'}:{},signal:AbortSignal.timeout(15000)});
    const body=await response.json().catch(()=>null);
    const ok=pathname==='/health'?response.status===200&&body?.ok===true:response.status===400&&body?.error?.code==='VALIDATION_ERROR';
    console.log(JSON.stringify({event:'deployed_endpoint_check',path:pathname,status:response.status,ok,request_id:/^[a-f0-9-]{36}$/.test(body?.error?.request_id??'')?body.error.request_id:undefined,probe:method==='POST'?'invalid_payload_no_signup':'health'}));
    if(!ok)process.exitCode=1;
   }
  }
 }catch(error){
  if(error instanceof ConfigurationError)logDiagnostic('error',{event:'dependency_failure',subsystem:'configuration',failure:'invalid_configuration',configuration_fields:error.issues.map(issue=>issue.split(':')[0])});
  else if(!(error instanceof DependencyError))logDiagnostic('error',{event:'dependency_failure',subsystem:'http',failure:'diagnostic_check_unavailable'});
  process.exitCode=1;
 }
});
