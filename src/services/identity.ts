import {randomUUID} from 'node:crypto';
import {createClient,type SupabaseClient} from '@supabase/supabase-js';
import type {Profile} from '@manji/shared-types';
import type {Config} from './config';
import type {Database} from './database';
import {sandboxAdmin} from './database';
import {ApiError,ensure,hash,secret,encrypt,passwordHash,passwordMatches,databaseError} from './security';
import {DependencyError,logDiagnostic} from './diagnostics';
function registrationAuthFailure(error:unknown):never{
 const source=error&&typeof error==='object'?error as {code?:unknown;status?:unknown}:{};
 const status=typeof source.status==='number'?source.status:0;
 const unavailable=status===0||status>=500;
 logDiagnostic(unavailable?'error':'warn',{event:'dependency_failure',subsystem:'auth.supabase',failure:unavailable?'registration_service_unavailable':'registration_rejected',upstream_code:source.code,upstream_status:status});
 if(unavailable)throw new DependencyError('auth.supabase','registration_service_unavailable','REGISTRATION_UNAVAILABLE','Layanan pendaftaran belum tersedia. Silakan coba kembali.');
 throw new ApiError(status===429?429:400,'REGISTRATION_FAILED','Pendaftaran belum dapat diproses. Periksa email dan kebijakan password.');
}
export type AccountView={profile:Profile;applications:Record<string,unknown>[];merchants:{merchant_id:string;role:string;merchants:{name:string};identifier:string;status:string}[]};
export type SessionTokens={access_token:string;refresh_token:string;expires_at:number;session_id:string;user_id:string};
export type UserIdentity={user_id:string;session_id:string;access_token:string};
export class Identity {
  private auth?:SupabaseClient;
  constructor(private db:Database,private c:Config){if(c.STORE_DRIVER==='supabase')this.auth=createClient(c.NEXT_PUBLIC_SUPABASE_URL!,c.NEXT_PUBLIC_SUPABASE_ANON_KEY!,{auth:{persistSession:false,autoRefreshToken:false}});}
  private jwtSession(token:string){try{return JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString()).session_id as string;}catch{throw new ApiError(401,'UNAUTHENTICATED','Sesi tidak valid');}}
  async register(email:string,password:string,displayName:string){
    const settings=await this.db.rpc<{registration_open:boolean}>('account_command',{p_actor:null,p_session:null,p_command:'public.configuration',p_data:{}});ensure(settings.registration_open,403,'REGISTRATION_CLOSED','Pendaftaran sedang ditutup');
    if(this.auth){
      let result;
      try{result=await this.auth.auth.signUp({email,password,options:{data:{display_name:displayName},emailRedirectTo:this.c.APP_BASE_URL+'/auth/confirm'}});}catch(error){registrationAuthFailure(error);}
      if(result.error)registrationAuthFailure(result.error);
      // If the project disables email confirmation, do not silently grant an application session.
      return {accepted:true,email_verification_required:true,delivery:'supabase_email',role:'PENDING'};
    }
    const sql=this.db.local!,id=randomUUID();
    try{
      await sql.transaction(async tx=>{await tx.query('insert into auth.users(id,email,raw_user_meta_data) values($1,$2,$3)',[id,email.toLowerCase(),JSON.stringify({display_name:displayName})]);await tx.query('insert into gateway_sandbox.identities(user_id,password_hash) values($1,$2)',[id,passwordHash(password)]);});
      await this.mail(id,'email');
    }catch(e){if(!(e as Error).message.includes('unique'))throw e;}
    return {accepted:true,email_verification_required:true,delivery:'sandbox_mailbox',role:'PENDING'};
  }
  private async mail(userId:string,type:'email'|'recovery'){
    const token=secret();await this.db.local!.query('insert into gateway_sandbox.mail(id,user_id,type,token_hash,token_encrypted,expires_at) values($1,$2,$3,$4,$5,now()+interval \'1 hour\')',[randomUUID(),userId,type,hash(token),encrypt(token,this.c.APP_ENCRYPTION_KEY)]);
  }
  async login(email:string|undefined,password:string,deviceName='Sesi pengguna'):Promise<SessionTokens>{
    if(this.auth){const {data,error}=await this.auth.auth.signInWithPassword({email:email??'',password});ensure(!error&&data.session,401,'LOGIN_FAILED','Email atau kata sandi tidak cocok, atau email belum diverifikasi');return this.acceptRemote(data.session.access_token,data.session.refresh_token,data.session.expires_at!,deviceName);}
    const sql=this.db.local!;const rows=await sql.query<{id:string;password_hash:string;email_confirmed_at:string|null}>(`select u.id,i.password_hash,u.email_confirmed_at from auth.users u join gateway_sandbox.identities i on i.user_id=u.id where ${email?'lower(u.email)=lower($1)':'u.id=$1'}`,[email??sandboxAdmin]);
    const row=rows.rows[0];ensure(row&&passwordMatches(password,row.password_hash),401,'LOGIN_FAILED','Email atau kata sandi tidak cocok');ensure(row.email_confirmed_at,403,'EMAIL_UNVERIFIED','Verifikasi email sebelum masuk');return this.localSession(row.id,randomUUID(),deviceName);
  }
  private async localSession(userId:string,sessionId:string,deviceName:string):Promise<SessionTokens>{
    const access='su_'+secret(),refresh='sr_'+sessionId+'.'+secret(),expires=Math.floor(Date.now()/1000)+3600;
    await this.db.rpc('account_command',{p_actor:userId,p_session:null,p_command:'profile.bootstrap',p_data:{}});
    await this.db.rpc('account_command',{p_actor:userId,p_session:sessionId,p_command:'session.open',p_data:{device_name:deviceName,access_hash:hash(access),refresh_hash:hash(refresh)}});
    await this.db.local!.query('insert into gateway_sandbox.access_tokens(secret_hash,user_id,session_id,expires_at) values($1,$2,$3,to_timestamp($4))',[hash(access),userId,sessionId,expires]);
    return {access_token:access,refresh_token:refresh,expires_at:expires,session_id:sessionId,user_id:userId};
  }
  private async acceptRemote(access:string,refresh:string,expires:number,deviceName:string):Promise<SessionTokens>{
    const verified=await this.auth!.auth.getUser(access);ensure(!verified.error&&verified.data.user,401,'UNAUTHENTICATED');const user=verified.data.user;ensure(user.email_confirmed_at,403,'EMAIL_UNVERIFIED');const sessionId=this.jwtSession(access);
    ensure(/^[a-f0-9-]{36}$/i.test(sessionId),401,'UNAUTHENTICATED');
    await this.db.rpc('account_command',{p_actor:user.id,p_session:null,p_command:'profile.bootstrap',p_data:{}});
    await this.db.rpc('account_command',{p_actor:user.id,p_session:sessionId,p_command:'session.open',p_data:{device_name:deviceName}});
    return {access_token:access,refresh_token:refresh,expires_at:expires,session_id:sessionId,user_id:user.id};
  }
  async verify(tokenHash:string,type:'email'|'recovery'):Promise<SessionTokens>{
    if(this.auth){const result=await this.auth.auth.verifyOtp({token_hash:tokenHash,type});ensure(!result.error&&result.data.session,400,'INVALID_EMAIL_TOKEN','Tautan tidak berlaku atau sudah digunakan');const s=result.data.session;return this.acceptRemote(s.access_token,s.refresh_token,s.expires_at!,'Verifikasi email');}
    const sql=this.db.local!;const result=await sql.query<{user_id:string}>('update gateway_sandbox.mail set used_at=now() where token_hash=$1 and type=$2 and used_at is null and expires_at>now() returning user_id',[hash(tokenHash),type]);ensure(result.rows[0],400,'INVALID_EMAIL_TOKEN','Tautan tidak berlaku atau sudah digunakan');
    const userId=result.rows[0].user_id;await sql.query('update auth.users set email_confirmed_at=coalesce(email_confirmed_at,now()) where id=$1',[userId]);return this.localSession(userId,randomUUID(),type==='recovery'?'Pemulihan password':'Verifikasi email');
  }
  async refresh(token:string):Promise<SessionTokens>{
    if(this.auth){const result=await this.auth.auth.refreshSession({refresh_token:token});ensure(!result.error&&result.data.session,401,'SESSION_EXPIRED','Sesi berakhir. Masuk kembali.');const s=result.data.session;return this.acceptRemote(s.access_token,s.refresh_token,s.expires_at!,'Sesi diperbarui');}
    const rows=await this.db.local!.query<{user_id:string;id:string;device_name:string}>('select user_id,id,device_name from manji_gateway.account_sessions where refresh_hash=$1 and revoked_at is null and expires_at>now()',[hash(token)]);const s=rows.rows[0];ensure(s,401,'SESSION_EXPIRED','Sesi berakhir. Masuk kembali.');return this.localSession(s.user_id,s.id,s.device_name);
  }
  async identify(token:string):Promise<UserIdentity>{
    if(this.auth){const result=await this.auth.auth.getUser(token);ensure(!result.error&&result.data.user,401,'UNAUTHENTICATED','Masuk atau perbarui sesi');return {user_id:result.data.user.id,session_id:this.jwtSession(token),access_token:token};}
    const rows=await this.db.local!.query<{user_id:string;session_id:string}>('select user_id,session_id from gateway_sandbox.access_tokens where secret_hash=$1 and expires_at>now()',[hash(token)]);const row=rows.rows[0];ensure(row,401,'UNAUTHENTICATED','Masuk atau perbarui sesi');return {...row,access_token:token};
  }
  async me(user:UserIdentity){return this.db.rpc<AccountView>('account_command',{p_actor:user.user_id,p_session:user.session_id,p_command:'account.me',p_data:{}});}
  async reset(email:string){
    if(this.auth){const result=await this.auth.auth.resetPasswordForEmail(email,{redirectTo:this.c.APP_BASE_URL+'/auth/confirm?type=recovery'});ensure(!result.error,503,'EMAIL_UNAVAILABLE','Layanan email belum tersedia');}
    else{const result=await this.db.local!.query<{id:string}>('select id from auth.users where lower(email)=lower($1)',[email]);if(result.rows[0])await this.mail(result.rows[0].id,'recovery');}
    return {accepted:true,delivery:this.auth?'supabase_email':'sandbox_mailbox'};
  }
  async resend(email:string){
    if(this.auth){const result=await this.auth.auth.resend({type:'signup',email,options:{emailRedirectTo:this.c.APP_BASE_URL+'/auth/confirm'}});ensure(!result.error,503,'EMAIL_UNAVAILABLE','Layanan email belum tersedia');}
    else{const r=await this.db.local!.query<{id:string}>('select id from auth.users where lower(email)=lower($1) and email_confirmed_at is null',[email]);if(r.rows[0])await this.mail(r.rows[0].id,'email');}
    return {accepted:true,delivery:this.auth?'supabase_email':'sandbox_mailbox'};
  }
  async changePassword(user:UserIdentity,password:string){
    if(this.auth){const result=await this.db.remote!.auth.admin.updateUserById(user.user_id,{password});ensure(!result.error,400,'PASSWORD_UPDATE_FAILED','Password belum dapat diperbarui');}
    else await this.db.local!.query('update gateway_sandbox.identities set password_hash=$1 where user_id=$2',[passwordHash(password),user.user_id]);
    const sessions=await this.db.rpc<{id:string}[]>('account_command',{p_actor:user.user_id,p_session:user.session_id,p_command:'sessions.list',p_data:{}});
    for(const s of sessions.filter(s=>s.id!==user.session_id))await this.db.rpc('account_command',{p_actor:user.user_id,p_session:user.session_id,p_command:'sessions.revoke',p_data:{id:s.id}});
    return {ok:true};
  }
  async logout(user:UserIdentity){await this.db.rpc('account_command',{p_actor:user.user_id,p_session:user.session_id,p_command:'sessions.revoke',p_data:{id:user.session_id}});if(this.db.remote){const result=await this.db.remote.auth.admin.signOut(user.access_token,'local');if(result.error&&!result.error.message.includes('session'))databaseError('UNAUTHENTICATED');}return {ok:true};}
}
