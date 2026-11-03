import path from 'node:path';
import {readFile,stat} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {z} from 'zod';
import type {SignedArtifact} from '../types/app-artifact';

const filename='manji-gateway-release.apk' as const;
const digest=z.string().regex(/^[a-f0-9]{64}$/);
const verificationReport=z.object({
 schema_version:z.literal(1),filename:z.literal(filename),application_id:z.literal('id.biz.manjifood.gateway'),
 version_code:z.literal(3),version_name:z.literal('0.3.0'),min_sdk:z.literal(26),target_sdk:z.literal(35),
 sha256:digest,size_bytes:z.number().int().positive().max(83_886_080),signer_sha256:digest,
 source_sha256:z.literal('1decb2582140ac3097fcecbedca408512a07269e4bfc1fc62db36f3fffd1fd46'),
 signature_verified:z.literal(true),v2:z.literal(true),v3:z.literal(true),alignment_verified:z.literal(true),
 payload_unchanged:z.literal(true),unsigned_preserved:z.literal(true),rebuilt:z.literal(false),
 verified_at:z.string().datetime(),
});
export function verifySignedArtifact(bytes:Buffer,report:unknown):SignedArtifact{
 const verified=verificationReport.parse(report),sha256=createHash('sha256').update(bytes).digest('hex');
 if(bytes.length!==verified.size_bytes||sha256!==verified.sha256)throw Error('Signed APK does not match its verification report');
 return {filename,size_bytes:bytes.length,sha256,signer_sha256:verified.signer_sha256,version_name:verified.version_name,version_code:verified.version_code,min_sdk:verified.min_sdk,download_path:'/aplikasi/manji-gateway-release.apk'};
}
export async function readSignedArtifact(){
 const cwd=process.cwd(),manifest=JSON.parse(await readFile(path.join(cwd,'package.json'),'utf8'));
 const directory=path.join(manifest.name==='@manji/api'?cwd:path.join(cwd,'web'),'aplikasi');
 const report=verificationReport.parse(JSON.parse(await readFile(path.join(directory,'manji-gateway-release.verification.json'),'utf8')));
 const file=path.join(directory,filename),info=await stat(file);
 if(!info.isFile()||info.size!==report.size_bytes)throw Error('Signed APK size does not match verification');
 const bytes=await readFile(file);
 return {bytes,metadata:verifySignedArtifact(bytes,report)};
}
export async function signedArtifactInfo():Promise<SignedArtifact|null>{try{return (await readSignedArtifact()).metadata;}catch{return null;}}
export async function signedArtifactResponse(head=false){
 try{
  const {bytes,metadata}=await readSignedArtifact();
  let offset=0;const body=head?null:new ReadableStream<Uint8Array>({pull(controller){if(offset===bytes.length){controller.close();return;}const end=Math.min(offset+65536,bytes.length);controller.enqueue(new Uint8Array(bytes.subarray(offset,end)));offset=end;}});
  return new Response(body,{headers:{'content-type':'application/vnd.android.package-archive','content-disposition':`attachment; filename="${metadata.filename}"`,'content-length':String(bytes.length),'x-checksum-sha256':metadata.sha256,'x-apk-certificate-sha256':metadata.signer_sha256,'x-apk-status':'signed','x-content-type-options':'nosniff','cache-control':'private, no-store, no-transform','referrer-policy':'no-referrer'}});
 }catch(error){
  const status=(error as NodeJS.ErrnoException).code==='ENOENT'?404:503;
  return new Response(head?null:JSON.stringify({error:{code:'SIGNED_ARTIFACT_UNAVAILABLE',message:'APK bertanda tangan belum tersedia atau gagal pemeriksaan integritas.',request_id:randomUUID()}}),{status,headers:{'content-type':'application/json','cache-control':'no-store'}});
 }
}
