import {createHash,createHmac,randomBytes,scryptSync,timingSafeEqual,createCipheriv,createDecipheriv} from 'node:crypto';
export class ApiError extends Error{constructor(public status:number,public code:string,message:string){super(message);}}
export function ensure(value:unknown,status=400,code='VALIDATION_ERROR',message='Permintaan tidak valid'):asserts value{if(!value)throw new ApiError(status,code,message);}
export const hash=(s:string|Buffer)=>createHash('sha256').update(s).digest('hex');
export const secret=()=>randomBytes(32).toString('hex');
export const hmac=(key:string,s:string)=>createHmac('sha256',key).update(s).digest('hex');
export function equal(a:string,b:string){const x=Buffer.from(a),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
export function passwordHash(password:string,salt=secret()){return salt+'.'+scryptSync(password,salt,32).toString('hex');}
export function passwordMatches(password:string,verifier:string){const [salt,digest]=verifier.split('.');return !!salt&&!!digest&&equal(scryptSync(password,salt,32).toString('hex'),digest);}
export function encrypt(value:string,key:string){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',Buffer.from(key,'hex'),iv);return Buffer.concat([iv,cipher.update(value),cipher.final(),cipher.getAuthTag()]).toString('base64');}
export function decrypt(value:string,key:string){const data=Buffer.from(value,'base64'),cipher=createDecipheriv('aes-256-gcm',Buffer.from(key,'hex'),data.subarray(0,12));cipher.setAuthTag(data.subarray(-16));return Buffer.concat([cipher.update(data.subarray(12,-16)),cipher.final()]).toString();}
export function cookieValue(req:Request,name:string){return req.headers.get('cookie')?.split(';').map(s=>s.trim()).find(s=>s.startsWith(name+'='))?.slice(name.length+1);}
export function databaseError(message:string):never{
  const codes:Record<string,[number,string]>={UNAUTHENTICATED:[401,'Masuk kembali untuk melanjutkan'],SESSION_REVOKED:[401,'Sesi telah dicabut'],EMAIL_UNVERIFIED:[403,'Verifikasi email terlebih dahulu'],FORBIDDEN:[403,'Akses tidak diizinkan'],ACCOUNT_SUSPENDED:[403,'Akun atau merchant dinonaktifkan'],MERCHANT_REQUIRED:[403,'Akses hanya untuk merchant yang disetujui'],NOT_FOUND:[404,'Data tidak ditemukan'],IDEMPOTENCY_CONFLICT:[409,'Kunci idempotensi sudah digunakan'],INVALID_STATE:[409,'Status tidak mengizinkan tindakan ini'],QR_REQUIRED:[409,'Daftarkan QR merchant asli terlebih dahulu'],DUPLICATE_REFERENCE:[409,'Referensi telah digunakan'],SOURCE_NOT_ALLOWED:[403,'Sumber notifikasi belum disetujui administrator'],DEVICE_EXPIRED:[401,'Hubungkan atau perbarui perangkat'],INVALID_CHALLENGE:[401,'Kode enrollment tidak berlaku'],PAYMENT_MISMATCH:[400,'Konfirmasi provider tidak cocok'],EVENT_CONFLICT:[409,'Konflik event provider'],RATE_LIMITED:[429,'Terlalu banyak permintaan'],VALIDATION_ERROR:[400,'Periksa format permintaan'],ALREADY_REVIEWED:[409,'Pengajuan sudah diproses'],REGISTRATION_CLOSED:[403,'Pendaftaran sedang ditutup']};
  for(const [code,[status,text]]of Object.entries(codes))if(message.includes(code))throw new ApiError(status,code,text);
  throw new ApiError(503,'DATABASE_UNAVAILABLE','Database belum tersedia');
}
