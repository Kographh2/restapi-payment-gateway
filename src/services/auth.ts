import type {Profile} from '@manji/shared-types';
import type {Config} from './config';
import type {Database} from './database';
import {Identity,type UserIdentity} from './identity';
import {ApiError,cookieValue,ensure,hash} from './security';
export type Principal={actor:string;session:string|null;merchant:string|null;kind:'user'|'api'|'device';subject:string|null;profile?:Profile;user?:UserIdentity;scopes?:string[]};
export async function authenticate(req:Request,c:Config,db:Database):Promise<Principal>{
  const token=req.headers.get('authorization')?.replace(/^Bearer /,'')??cookieValue(req,'manji_access');ensure(token,401,'UNAUTHENTICATED','Masuk terlebih dahulu');
  const credential=token.match(/^(mg_sbx|mg_live|md)_([a-f0-9-]{36})\.([a-f0-9]{64})$/i);
  if(credential){
    ensure((credential[1]!=='mg_live'||c.PAYMENT_ENV==='production')&&(credential[1]!=='mg_sbx'||c.PAYMENT_ENV==='sandbox'),401,'ENVIRONMENT_MISMATCH','Credential berasal dari lingkungan berbeda');
    const kind=credential[1]==='md'?'device':'api';
    const row=await db.rpc<{id:string;merchant_id:string;created_by?:string;user_id?:string;scopes?:string[]}>('lookup_credential',{p_kind:kind,p_id:credential[2],p_hash:hash(token)});
    return {actor:(row.created_by??row.user_id)!,session:null,merchant:row.merchant_id,kind,subject:row.id,scopes:row.scopes};
  }
  const identity=new Identity(db,c),user=await identity.identify(token),account=await identity.me(user);
  const requested=req.headers.get('x-merchant-id')??cookieValue(req,'manji_merchant');
  if(requested)ensure(account.merchants.some(x=>x.merchant_id===requested),404,'NOT_FOUND','Merchant tidak ditemukan');
  return {actor:user.user_id,session:user.session_id,merchant:requested??(account.merchants.length===1?account.merchants[0].merchant_id:null),kind:'user',subject:null,profile:account.profile,user};
}
export function userOnly(p:Principal){ensure(p.kind==='user'&&p.user,403,'FORBIDDEN','Gunakan sesi pengguna');return p.user;}
export function adminOnly(p:Principal){userOnly(p);ensure(p.profile?.role==='ADMIN'&&p.profile.status==='ACTIVE',403,'FORBIDDEN','Memerlukan akses administrator');}
export function merchantId(p:Principal){if(!p.merchant)throw new ApiError(p.profile?.role==='MERCHANT'?409:403,p.profile?.role==='MERCHANT'?'SELECT_MERCHANT':'MERCHANT_REQUIRED',p.profile?.role==='MERCHANT'?'Pilih merchant terlebih dahulu':'Akun belum memiliki akses merchant');return p.merchant;}
