import {PGlite} from '@electric-sql/pglite';
import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import {readFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import type {Config} from './config';
import {passwordHash} from './security';
import {applicationRoot} from './application-root';
import {databaseFailure} from './database-failure';
export const schema='manji_gateway';
export const sandboxAdmin='10000000-0000-4000-8000-000000000001';
// Package-local SQL works from web and the existing monorepo entry points.
// An explicit repository override still supports operator-selected fixtures.
const root=process.env.GATEWAY_REPO_ROOT??applicationRoot();
export const migrations=['202611020001_manji_schema.sql','202611020002_manji_commands.sql','202611020003_manji_provider_worker.sql','202611020004_manji_account_idempotency.sql','202611020005_app_distribution.sql'];
export interface Database {rpc<T=unknown>(name:string,args:Record<string,unknown>):Promise<T>;local?:PGlite;remote?:SupabaseClient;}
export class LocalDatabase implements Database {
  lastError:string|undefined;
  constructor(public local:PGlite){}
  async rpc<T=unknown>(name:string,args:Record<string,unknown>):Promise<T>{
    if(!/^[a-z_]+$/.test(name))throw new Error('Invalid function');const keys=Object.keys(args);if(keys.some(k=>!/^p_[a-z_]+$/.test(k)))throw new Error('Invalid argument');
    const values=keys.map(k=>typeof args[k]==='object'&&args[k]!==null?JSON.stringify(args[k]):args[k]);
    try{const result=await this.local.query<{result:T}>(`select ${schema}.${name}(${keys.map((k,i)=>`${k} => $${i+1}`).join(',')}) as result`,values);return result.rows[0].result;}catch(e){this.lastError=(e as Error).message;databaseFailure(e,'local',name,args);}
  }
}
export class SupabaseDatabase implements Database {
  remote:SupabaseClient;
  constructor(c:Config){this.remote=createClient(c.NEXT_PUBLIC_SUPABASE_URL!,c.SUPABASE_SERVICE_ROLE_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});}
  async rpc<T=unknown>(name:string,args:Record<string,unknown>):Promise<T>{
    let result;
    try{result=await this.remote.schema(schema).rpc(name,args);}catch(error){databaseFailure(error,'supabase',name,args,0);}
    if(result.error)databaseFailure(result.error,'supabase',name,args,result.status);
    return result.data as T;
  }
}
export async function localDatabase(directory?:string,adminPassword?:string){
  if(directory)await mkdir(directory,{recursive:true});const sql=new PGlite(directory);const existing=await sql.query<{exists:boolean}>("select exists(select 1 from pg_namespace where nspname='manji_gateway')");
  if(!existing.rows[0].exists){
    await sql.exec(await readFile(path.join(root,'supabase/seed/local-auth-fixture.sql'),'utf8'));
    for(const name of migrations)await sql.exec(await readFile(path.join(root,'supabase/migrations',name),'utf8'));
    if(adminPassword){
      await sql.query("insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,'admin@sandbox.invalid',now(),'{\"display_name\":\"Administrator Sandbox\"}')",[sandboxAdmin]);
      await sql.query("update manji_gateway.profiles set role='ADMIN' where id=$1",[sandboxAdmin]);
      await sql.query('insert into gateway_sandbox.identities(user_id,password_hash) values($1,$2)',[sandboxAdmin,passwordHash(adminPassword)]);
    }
  }
  const distribution=await sql.query<{installed:boolean}>("select to_regprocedure('manji_gateway.app_release_command(text,jsonb)') is not null installed");
  if(!distribution.rows[0].installed)await sql.exec(await readFile(path.join(root,'supabase/migrations/202611020005_app_distribution.sql'),'utf8'));
  return new LocalDatabase(sql);
}
let singleton:Promise<Database>|undefined;
export function database(c:Config){return singleton??=c.STORE_DRIVER==='supabase'?Promise.resolve(new SupabaseDatabase(c)):localDatabase(c.dataDir,c.SANDBOX_LOGIN_SECRET);}
