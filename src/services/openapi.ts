import {z} from 'zod';
import * as v from '@manji/validation';
import {releaseManifest,releaseChannel} from '@manji/validation/releases';
type Schema=Record<string,unknown>;
function convert(s:z.ZodTypeAny):Schema{
  const d=s._def;switch(d.typeName){
    case 'ZodOptional':case 'ZodDefault':return convert(d.innerType);
    case 'ZodEffects':return convert(d.schema);
    case 'ZodNullable':return {anyOf:[convert(d.innerType),{type:'null'}]};
    case 'ZodObject':{const shape=d.shape() as Record<string,z.ZodTypeAny>;return {type:'object',additionalProperties:false,properties:Object.fromEntries(Object.entries(shape).map(([k,x])=>[k,convert(x)])),required:Object.entries(shape).filter(([,x])=>!x.isOptional()).map(([k])=>k)};}
    case 'ZodArray':return {type:'array',items:convert(d.type),...d.minLength?{minItems:d.minLength.value}:{},...d.maxLength?{maxItems:d.maxLength.value}:{}};
    case 'ZodEnum':return {type:'string',enum:d.values};
    case 'ZodLiteral':return {const:d.value,type:typeof d.value};
    case 'ZodBoolean':return {type:'boolean'};
    case 'ZodNumber':{const checks=d.checks as {kind:string;value:number}[];return {type:checks.some(c=>c.kind==='int')?'integer':'number',...Object.fromEntries(checks.filter(c=>['min','max'].includes(c.kind)).map(c=>[c.kind==='min'?'minimum':'maximum',c.value]))};}
    case 'ZodString':{const result:Schema={type:'string'};for(const check of d.checks as {kind:string;value:number;regex:RegExp}[]){if(check.kind==='min')result.minLength=check.value;if(check.kind==='max')result.maxLength=check.value;if(check.kind==='email')result.format='email';if(check.kind==='uuid')result.format='uuid';if(check.kind==='datetime')result.format='date-time';if(check.kind==='url')result.format='uri';if(check.kind==='regex')result.pattern=check.regex.source;}return result;}
    default:return {};
  }
}
type Operation={method:'get'|'post'|'delete';path:string;summary:string;tag:string;body?:z.ZodTypeAny;public?:boolean;description?:string;created?:boolean;accepted?:boolean;query?:boolean;appChannel?:boolean;redirect?:boolean;binary?:boolean;unsigned?:boolean;signedArchive?:boolean;archiveRedirect?:boolean;response?:z.ZodTypeAny};
const empty=z.object({}).strict(),email=z.object({email:z.string().email()}).strict(),idBody=z.object({challenge_id:v.uuid,challenge:z.string().length(64)}).strict();
const publicAppRelease=releaseManifest.innerType().omit({apk_key:true,checks:true,build:true,profile:true,schema_version:true,screenshots:true}).extend({download_path:z.string(),screenshots:z.array(z.object({url:z.string(),caption:z.string(),width:z.number().int(),height:z.number().int()}))});
const appVersion=z.object({available:z.boolean(),channel:releaseChannel,distribution_environment:z.enum(['production','test']),release:publicAppRelease.nullable(),history:z.array(publicAppRelease)});
export const operations:Operation[]=[
  {method:'get',path:'/api/v1/app/download',summary:'Unduh APK MANJI Gateway bertanda tangan',tag:'Aplikasi Android',public:true,archiveRedirect:true,description:'307 ke /aplikasi/manji-gateway-release.apk pada origin yang sama. APK harus tersedia bersama laporan verifikasi signing yang cocok. Arsip unsigned tetap tersedia pada endpoint terpisah; katalog dan updater tidak diubah.'},
  {method:'get',path:'/aplikasi/manji-gateway-release.apk',summary:'Berkas APK existing setelah signing',tag:'Aplikasi Android',public:true,signedArchive:true,description:'APK yang ditandatangani tanpa rebuild. Laporan verifikasi dan SHA-256 berkas diperiksa sebelum pengiriman. 404 jika belum tersedia; 503 jika bukti verifikasi atau checksum gagal. Mendukung HEAD. Header X-Checksum-SHA256 dan X-APK-Certificate-SHA256 berisi checksum berkas dan fingerprint sertifikat.'},
  {method:'get',path:'/api/v1/app/unsigned/download',summary:'Unduh arsip APK unsigned untuk pengembangan',tag:'Aplikasi Android',public:true,unsigned:true,description:'Berkas yang ada di web/aplikasi, disajikan tanpa modifikasi. Belum ditandatangani, tidak dapat dipasang langsung, bukan rilis produksi dan tidak masuk katalog updater. Header X-APK-Status: unsigned-not-installable. Tidak memerlukan Storage eksternal.'},
  {method:'get',path:'/v1/app/version',summary:'Versi APK resmi, kanal dan riwayat',tag:'Aplikasi Android',public:true,appChannel:true,response:appVersion,description:'Publik. Default stable, beta opsional. available=false jika katalog kosong; 503 jika distribusi belum dikonfigurasi. Android membandingkan version_code lokal dan menolak downgrade. Riwayat maksimal 30 rilis aktif per kanal; object key privat tidak dikirim.'},
  {method:'get',path:'/v1/app/latest/download',summary:'Mulai unduh APK resmi terbaru',tag:'Aplikasi Android',public:true,appChannel:true,redirect:true,description:'307 ke tiket backend 120 detik, terikat ID dan hash APK. Tidak ada debug/unsigned di produksi. 503 APP_RELEASE_UNAVAILABLE jika belum ada rilis. Ikuti Location pada origin HTTPS yang sama; final response application/vnd.android.package-archive dan X-Checksum-SHA256.'},
  {method:'get',path:'/v1/app/releases/{id}/download',summary:'Unduh versi tertentu dari riwayat',tag:'Aplikasi Android',public:true,redirect:true,description:'307 tiket backend sementara; rilis yang ditarik ditolak. Signature, identitas paket dan kode versi tetap diperiksa Android.'},
  {method:'get',path:'/v1/app/releases/{id}/file',summary:'Berkas APK terverifikasi melalui tiket',tag:'Aplikasi Android',public:true,binary:true,description:'Tiket wajib dari backend. 200 APK, 206 untuk Range tunggal bytes=start-end, 416 range tidak valid; 401 tiket palsu/kedaluwarsa, 404 rilis ditarik, 503 hash/storage gagal. Revokasi dan SHA-256 diperiksa sebelum byte disajikan.'},
  {method:'get',path:'/v1/app/releases/{id}/screenshots/{index}',summary:'Cuplikan layar asli untuk rilis',tag:'Aplikasi Android',public:true,binary:true,description:'Gambar dari private storage yang lolos checksum; indeks 0–7. Tidak ada preview hasil rekayasa yang diklaim sebagai screenshot.'},
  {method:'get',path:'/health',summary:'Kesehatan dan lingkungan backend',tag:'Operasional',public:true},
  {method:'post',path:'/v1/auth/register',accepted:true,summary:'Daftar akun PENDING',tag:'Autentikasi',body:v.register,public:true,description:'Role dari klien ditolak. Verifikasi email dan peninjauan admin diperlukan; tidak ada hak merchant/admin otomatis.'},
  {method:'post',path:'/v1/auth/login',summary:'Login email/password',tag:'Autentikasi',body:v.login,public:true},
  {method:'post',path:'/v1/auth/verify',summary:'Verifikasi tautan email/pemulihan',tag:'Autentikasi',public:true,body:z.object({token_hash:z.string().min(16).max(512),type:z.enum(['email','recovery'])}).strict()},
  {method:'post',path:'/v1/auth/refresh',summary:'Perbarui sesi pengguna',tag:'Autentikasi',public:true,body:z.object({refresh_token:z.string().optional()}).strict(),description:'Browser memakai cookie HttpOnly. Android mengirim refresh_token dari penyimpanan terenkripsi.'},
  {method:'post',path:'/v1/auth/reset-password',accepted:true,summary:'Minta pemulihan password',tag:'Autentikasi',public:true,body:email},
  {method:'post',path:'/v1/auth/resend-verification',accepted:true,summary:'Kirim ulang verifikasi',tag:'Autentikasi',public:true,body:email},
  {method:'get',path:'/v1/auth/me',summary:'Profil, role, pengajuan dan membership',tag:'Autentikasi'},
  {method:'post',path:'/v1/auth/logout',summary:'Logout aman dan cabut sesi',tag:'Autentikasi',body:empty},
  {method:'post',path:'/v1/auth/password',summary:'Ubah password dan cabut sesi lain',tag:'Autentikasi',body:z.object({password:v.password}).strict()},
  {method:'get',path:'/v1/auth/sessions',summary:'Daftar sesi akun',tag:'Autentikasi'},
  {method:'delete',path:'/v1/auth/sessions/{id}',summary:'Cabut sesi akun',tag:'Autentikasi'},
  {method:'post',path:'/v1/merchant-applications',summary:'Ajukan akses merchant',tag:'Akun',body:v.application,created:true},
  {method:'post',path:'/v1/auth/device/enroll',summary:'Mulai enrollment perangkat',tag:'Perangkat',body:v.enroll,description:'Sesi MERCHANT atau key Layer A ENROLLMENT. Allowlist harus merupakan sumber yang disetujui admin; tantangan berlaku 5 menit.'},
  {method:'post',path:'/v1/auth/device/redeem',summary:'Tukar tantangan dengan token perangkat',tag:'Perangkat',body:idBody,description:'Identitas pengaju yang sama. Token perangkat berlaku 15 menit; credential enrollment tidak disimpan permanen di Android.'},
  {method:'post',path:'/v1/devices/events',summary:'Kirim sinyal minimal UNTRUSTED',tag:'Perangkat',body:v.signal,description:'Hanya token perangkatnya sendiri. Kandidat nominal/waktu tidak pernah menetapkan PAID atau mengirim payment.verified.'},
  {method:'get',path:'/v1/devices/status',summary:'Status perangkat terautentikasi',tag:'Perangkat'},
  {method:'get',path:'/v1/merchant/devices',summary:'Daftar perangkat merchant',tag:'Perangkat'},
  {method:'post',path:'/v1/merchant/devices/{id}/revoke',summary:'Cabut perangkat',tag:'Perangkat',body:empty},
  {method:'post',path:'/v1/merchant/devices/{id}/rotate',summary:'Rotasi token perangkat',tag:'Perangkat',body:empty},
  {method:'post',path:'/v1/payments',summary:'Buat permintaan pembayaran',tag:'Pembayaran',body:v.payment,created:true,description:'Integer IDR 1–10.000.000, dapat dibatasi lebih rendah oleh konfigurasi sistem. STATIC_QRIS mempertahankan gambar asli. PROVIDER_DYNAMIC_QRIS mengembalikan 503 sampai provider resmi disetujui.'},
  {method:'get',path:'/v1/payments',summary:'Riwayat pembayaran berpaginasi',tag:'Pembayaran',query:true},
  {method:'get',path:'/v1/payments/{id}',summary:'Detail dan kronologi pembayaran',tag:'Pembayaran'},
  {method:'get',path:'/v1/payments/{id}/status',summary:'Status pembayaran dari server',tag:'Pembayaran'},
  {method:'post',path:'/v1/payments/{id}/cancel',summary:'Batalkan tagihan belum terverifikasi',tag:'Pembayaran',body:empty,description:'Pembatalan dicatat sebagai FAILED dengan failure_reason=merchant_canceled. Tidak mengubah PAID.'},
  {method:'get',path:'/v1/merchant/profile',summary:'Profil dan konfigurasi merchant',tag:'Merchant'},
  {method:'post',path:'/v1/qr-sources',summary:'Daftarkan gambar QR merchant asli',tag:'Merchant',created:true,body:z.object({mime:z.enum(['image/png','image/jpeg']),bytes_base64:z.string().max(950000),ownership_confirmed:z.literal(true)}).strict()},
  {method:'get',path:'/v1/qr-sources/{id}/image',summary:'Ambil gambar asli terautentikasi',tag:'Merchant'},
  {method:'get',path:'/v1/merchant/api-keys',summary:'Daftar identifier tanpa secret',tag:'Credential'},
  {method:'post',path:'/v1/merchant/api-keys',summary:'Buat credential Layer A/B',tag:'Credential',created:true,body:v.apiKey,description:'ENROLLMENT hanya devices:enroll. INTEGRATION untuk server website dengan scope pembayaran/webhook. Hanya verifier di-hash yang disimpan. Secret dihilangkan dari cache; retry penerbitan mengembalikan 409 SECRET_ALREADY_ISSUED, gunakan rotasi/enrollment ulang jika respons pertama hilang.'},
  {method:'delete',path:'/v1/merchant/api-keys/{id}',summary:'Cabut credential',tag:'Credential'},
  {method:'post',path:'/v1/merchant/api-keys/{id}/rotate',summary:'Rotasi credential; secret sekali tampil',tag:'Credential',body:empty},
  {method:'post',path:'/v1/webhooks/endpoints',summary:'Daftarkan penerima webhook',tag:'Webhook',body:v.endpoint,created:true,description:'Signing secret terpisah. HTTPS, allowlist host operator dan challenge verifikasi wajib.'},
  {method:'get',path:'/v1/webhooks/endpoints',summary:'Daftar penerima tanpa secret',tag:'Webhook'},
  {method:'delete',path:'/v1/webhooks/endpoints/{id}',summary:'Nonaktifkan penerima webhook',tag:'Webhook'},
  {method:'post',path:'/v1/webhooks/endpoints/{id}/test',summary:'Kirim endpoint.test non-finansial',tag:'Webhook',body:empty},
  {method:'post',path:'/v1/webhooks/endpoints/{id}/rotate',summary:'Rotasi signing secret dan verifikasi ulang',tag:'Webhook',body:empty},
  {method:'get',path:'/v1/realtime/config',summary:'Konfigurasi Supabase Realtime terotorisasi',tag:'Realtime',description:'JWT pengguna berumur pendek dan anon key publik, bukan service role. Subscribe manji_gateway.payment_requests dengan filter merchant_id. RLS tetap memeriksa role, status, sesi dan membership.'},
  {method:'get',path:'/v1/admin/overview',summary:'Operasional khusus ADMIN',tag:'Administrator'},
  {method:'post',path:'/v1/admin/applications/{id}/review',summary:'Setujui/tolak pengajuan',tag:'Administrator',body:z.object({action:z.enum(['approve','reject']),note:z.string().min(3).max(500)}).strict()},
  {method:'post',path:'/v1/admin/accounts/{id}/status',summary:'Suspend/aktifkan akun non-admin',tag:'Administrator',body:z.object({status:z.enum(['ACTIVE','SUSPENDED'])}).strict()},
  {method:'post',path:'/v1/admin/merchants/{id}/status',summary:'Suspend/aktifkan merchant',tag:'Administrator',body:z.object({status:z.enum(['ACTIVE','SUSPENDED'])}).strict()},
  {method:'post',path:'/v1/admin/configuration',summary:'Konfigurasi dan sumber notifikasi berizin',tag:'Administrator',body:v.sourceConfig},
  {method:'post',path:'/v1/admin/api-keys/{id}/revoke',summary:'Cabut credential merchant oleh ADMIN',tag:'Administrator',body:empty},
  {method:'post',path:'/v1/admin/devices/{id}/revoke',summary:'Cabut perangkat oleh ADMIN',tag:'Administrator',body:empty},
  {method:'post',path:'/v1/admin/merchants/{id}/enrollment-credential',summary:'Credential enrollment 15 menit dari ADMIN',tag:'Administrator',body:empty,created:true},
  {method:'get',path:'/v1/privacy/export',summary:'Ekspor snapshot merchant',tag:'Merchant'},
  {method:'delete',path:'/v1/privacy/signals',summary:'Hapus sinyal minimal dan audit tindakan',tag:'Merchant',body:empty},
  {method:'post',path:'/v1/provider/webhook/official',summary:'Callback provider resmi — belum aktif',tag:'Provider',public:true,description:'Selalu 503 PROVIDER_NOT_ONBOARDED. Tidak ada algoritma GoPay atau akses provider yang dikarang.'},
  {method:'post',path:'/v1/sandbox/provider/webhook',summary:'Callback HMAC protokol sandbox lokal',tag:'Sandbox',public:true,body:v.mockEvent,description:'X-Mock-Signature = HMAC-SHA256(body mentah, MOCK_PROVIDER_SECRET). Bukan algoritma GoPay. Timestamp maksimal ±5 menit. Tidak dapat menetapkan PAID produksi.'},
  {method:'post',path:'/v1/sandbox/confirm',summary:'Konfirmasi uji merchant lokal',tag:'Sandbox',body:z.object({payment_id:v.uuid}).strict(),description:'Sandbox saja, hasil SIMULATED_PAID atau REVIEW_REQUIRED. Tidak ada sukses finansial/receipt/speech nyata.'},
];
export function openapi(base=process.env.API_BASE_URL??'https://api.manjifood.biz.id'){
  const paths:Record<string,Record<string,unknown>>={};
  for(const op of operations){const parameters:Schema[]=[];if(op.path.includes('{id}'))parameters.push({in:'path',name:'id',required:true,schema:{type:'string',format:'uuid'}});if(!op.public&&op.method!=='get'&&!['/v1/auth/login','/v1/auth/register','/v1/auth/refresh','/v1/auth/verify','/v1/auth/logout','/v1/auth/password','/v1/auth/merchant'].includes(op.path))parameters.push({in:'header',name:'Idempotency-Key',required:true,schema:{type:'string',minLength:8,maxLength:128}});if(op.tag==='Pembayaran'||op.tag==='Merchant')parameters.push({in:'header',name:'X-Merchant-Id',required:false,schema:{type:'string',format:'uuid'},description:'Pilihan membership untuk akun multi-merchant'});
    if(op.query){const shape=v.pagination._def.shape();for(const [name,s]of Object.entries(shape))parameters.push({in:'query',name,required:false,schema:convert(s)});}
    if(op.appChannel)parameters.push({in:'query',name:'channel',required:false,schema:{type:'string',enum:['stable','beta'],default:'stable'}});
    if(op.path==='/v1/app/version')parameters.push({in:'query',name:'history_limit',required:false,schema:{type:'integer',minimum:0,maximum:30,default:30},description:'Android uses 0 for a lightweight update check.'});
    if(op.path.includes('{index}'))parameters.push({in:'path',name:'index',required:true,schema:{type:'integer',minimum:0,maximum:7}});
    if(op.path.endsWith('/file'))parameters.push({in:'query',name:'ticket',required:true,schema:{type:'string',maxLength:1024}},{in:'header',name:'Range',required:false,schema:{type:'string'},example:'bytes=0-1023'});
    const operation:Schema={summary:op.summary,description:op.description??'',operationId:op.method+'_'+op.path.replace(/\W/g,'_'),tags:[op.tag],security:op.public?[]:[{bearer:[]}],parameters,responses:{[op.accepted?'202':op.created?'201':'200']:{description:op.created?'Created':'Respons berhasil. Status finansial hanya berasal dari provider resmi.'},default:{description:'Kesalahan terstruktur',content:{'application/json':{schema:{$ref:'#/components/schemas/Error'}}}}}};
    if(op.body)operation.requestBody={required:true,content:{'application/json':{schema:convert(op.body)}}};paths[op.path]??={};paths[op.path][op.method]=operation;
    if(op.unsigned)operation.responses={'200':{description:'Existing unsigned development APK; not directly installable',headers:{'X-APK-Status':{schema:{type:'string',const:'unsigned-not-installable'}},'X-Checksum-SHA256':{schema:{type:'string'}}},content:{'application/vnd.android.package-archive':{schema:{type:'string',format:'binary'}}}},'404':{description:'APK not present in deployment'},'503':{description:'APK cannot be read'}};
    if(op.archiveRedirect)operation.responses={'307':{description:'Same-origin signed APK URL',headers:{Location:{schema:{type:'string',const:'/aplikasi/manji-gateway-release.apk'}}}}};
    if(op.signedArchive)operation.responses={'200':{description:'Existing signed APK with a matching verification report and checksum',headers:{'X-Checksum-SHA256':{schema:{type:'string'}},'X-APK-Certificate-SHA256':{schema:{type:'string'}}},content:{'application/vnd.android.package-archive':{schema:{type:'string',format:'binary'}}}},'404':{description:'Signed APK or verification report not present'},'503':{description:'Verification report or APK integrity check failed'}};
    if(op.redirect)operation.responses={'307':{description:'Temporary backend download ticket',headers:{Location:{schema:{type:'string'}}}},'401':{description:'Invalid/expired ticket'},'404':{description:'Release unavailable/revoked'},'503':{description:'Release/signing/storage not ready'}};
    if(op.response)operation.responses={'200':{description:'Current approved app distribution catalog',content:{'application/json':{schema:convert(op.response)}}},'503':{description:'Distribution not configured or metadata invalid'}};
    if(op.binary)operation.responses={'200':{description:'Integrity-checked private artifact',content:{[op.path.endsWith('/file')?'application/vnd.android.package-archive':'image/png']:{schema:{type:'string',format:'binary'}}}},'206':{description:'Single byte range (APK only)'},'401':{description:'Invalid/expired download ticket'},'404':{description:'Release unavailable/revoked'},'416':{description:'Invalid byte range'},'503':{description:'Artifact unavailable or integrity check failed'}};
  }
  return {openapi:'3.1.0',info:{title:'MANJI Gateway API',version:'0.2.0',description:'Merchant-owned QRIS monitoring. Payment detected tidak sama dengan Payment verified. Roles PENDING/USER tidak mengakses merchant. Provider resmi dinonaktifkan sampai disetujui.'},servers:[{url:base,description:'Origin konfigurasi; ketersediaan produksi harus diverifikasi setelah deployment'}],components:{securitySchemes:{bearer:{type:'http',scheme:'bearer',description:'JWT pengguna atau credential mg_sbx_/mg_live_/md_. Kunci integrasi hanya pada server; Android menukar enrollment credential untuk token perangkat.'}},schemas:{Error:{type:'object',properties:{error:{type:'object',required:['code','message','request_id'],properties:{code:{type:'string'},message:{type:'string'},request_id:{type:'string',format:'uuid'}}}}}}},paths};
}
