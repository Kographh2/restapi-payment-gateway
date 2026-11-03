import {mockEvent} from '@manji/validation';
import type {Config} from './config';
import type {Database} from './database';
import {ApiError,ensure,equal,hash,hmac} from './security';
const verifiedProof:unique symbol=Symbol('verified-by-server-adapter');
export type VerifiedEvent=ReturnType<typeof mockEvent.parse>&{provider:string;fingerprint:string;[verifiedProof]:true};
export interface PaymentProvider{verify(raw:string,signature:string|null,now:number):Promise<VerifiedEvent>;}
/** Local sandbox protocol only; never a GoPay signature algorithm. */
export class MockProviderAdapter implements PaymentProvider{
  constructor(private c:Config){}
  async verify(raw:string,signature:string|null,now=Date.now()):Promise<VerifiedEvent>{
    ensure(this.c.PAYMENT_ENV==='sandbox'&&this.c.PROVIDER_MODE==='mock'&&this.c.MOCK_PROVIDER_SECRET,404,'NOT_FOUND');
    ensure(signature&&equal(signature,hmac(this.c.MOCK_PROVIDER_SECRET,raw)),401,'INVALID_SIGNATURE','Tanda tangan tidak valid');const event=mockEvent.parse(JSON.parse(raw));
    ensure(Math.abs(now-event.timestamp*1000)<=300000,401,'STALE_EVENT','Event kedaluwarsa');return {...event,provider:'mock',fingerprint:hash(JSON.stringify({...event,timestamp:undefined})),[verifiedProof]:true};
  }
}
export class OfficialProviderAdapter implements PaymentProvider{
  async verify():Promise<VerifiedEvent>{throw new ApiError(503,'PROVIDER_NOT_ONBOARDED','Provider resmi belum disetujui dan diaktifkan');}
  async createDynamic():Promise<never>{throw new ApiError(503,'DYNAMIC_QRIS_UNAVAILABLE','QRIS dinamis memerlukan integrasi provider resmi yang disetujui');}
}
export async function commitVerified(db:Database,event:VerifiedEvent,c:Config){ensure(event[verifiedProof]===true,401,'UNVERIFIED_EVENT');return db.rpc('provider_event',{p_event:event,p_fingerprint:event.fingerprint,p_environment:c.PAYMENT_ENV});}
