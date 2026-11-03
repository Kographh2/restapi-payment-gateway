import assert from 'node:assert/strict';
import {test} from 'node:test';
import {randomUUID} from 'node:crypto';
import {localDatabase} from '../src/services/database';
import {OfficialProviderAdapter} from '../src/services/providers';
import {readFile} from 'node:fs/promises';

test('signup profile, merchant application and authorized review work with provider disabled; RLS and exposure repair preserve security',async()=>{
 const db=await localDatabase();
 try{
  const admin=randomUUID(),user=randomUUID(),adminSession=randomUUID(),userSession=randomUUID();
  for(const [id,email]of [[admin,'admin@example.invalid'],[user,'user@example.invalid']])await db.local.query('insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values($1,$2,now(),$3)',[id,email,JSON.stringify({role:'ADMIN',display_name:'Fixture'})]);
  assert.equal((await db.local.query<{role:string}>('select role from manji_gateway.profiles where id=$1',[user])).rows[0].role,'PENDING');
  await db.local.query("update manji_gateway.profiles set role='ADMIN' where id=$1",[admin]);
  for(const [actor,session]of [[admin,adminSession],[user,userSession]])await db.rpc('account_command',{p_actor:actor,p_session:session,p_command:'session.open',p_data:{}});
  await assert.rejects(new OfficialProviderAdapter().verify(),{code:'PROVIDER_NOT_ONBOARDED'});
  const app=await db.rpc<{id:string}>('account_command',{p_actor:user,p_session:userSession,p_command:'applications.submit',p_data:{business_name:'Fixture Merchant',business_description:'Local authorization fixture only',phone:'+628123456789'}});
  await assert.rejects(db.rpc('account_command',{p_actor:user,p_session:userSession,p_command:'admin.application.review',p_data:{id:app.id,action:'approve',note:'Unauthorized fixture'}}),{code:'FORBIDDEN'});
  await db.rpc('account_command',{p_actor:admin,p_session:adminSession,p_command:'admin.application.review',p_data:{id:app.id,action:'approve',note:'Authorized fixture'}});
  assert.equal((await db.local.query<{role:string}>('select role from manji_gateway.profiles where id=$1',[user])).rows[0].role,'MERCHANT');
  const before=await db.local.query<{tablename:string;rowsecurity:boolean}>('select tablename,rowsecurity from pg_tables where schemaname=$1 order by tablename',['manji_gateway']);
  assert.ok(before.rows.every(row=>row.rowsecurity===true));
  const repair=await readFile(new URL('../supabase/scripts/expose-manji-schema.sql',import.meta.url),'utf8');
  await db.local.exec("create role authenticator;alter role authenticator set pgrst.db_schemas='public,existing_food_schema';");
  await db.local.exec(repair);
  const setting=await db.local.query<{rolconfig:string[]}>('select rolconfig from pg_roles where rolname=$1',['authenticator']);
  assert.ok(setting.rows[0].rolconfig.includes('pgrst.db_schemas=public,existing_food_schema,manji_gateway'));
  await db.local.exec(repair);
  assert.deepEqual((await db.local.query('select tablename,rowsecurity from pg_tables where schemaname=$1 order by tablename',['manji_gateway'])).rows,before.rows);
  await assert.rejects(db.local.transaction(async tx=>{await tx.exec('set local role anon');await tx.exec('select * from manji_gateway.profiles');}));
  await assert.rejects(db.local.transaction(async tx=>{await tx.exec('set local role authenticated');await tx.exec("select manji_gateway.provider_event('{}','x','production')");}));
  await db.local.exec('alter role authenticator reset pgrst.db_schemas');
  await assert.rejects(db.local.exec(repair),/EXPOSE_WITH_DASHBOARD/);
  await db.local.exec('rollback');
 }finally{await db.local.close();}
});
