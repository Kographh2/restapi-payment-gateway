import {randomUUID} from 'node:crypto';
import {readUnsignedArtifact} from '@/services/unsigned-artifact';

export const runtime='nodejs';
export const dynamic='force-dynamic';
export async function GET(){
 try{
  const {bytes,metadata}=await readUnsignedArtifact();
  let offset=0;const body=new ReadableStream<Uint8Array>({pull(controller){if(offset===bytes.length){controller.close();return;}const end=Math.min(offset+65536,bytes.length);controller.enqueue(new Uint8Array(bytes.subarray(offset,end)));offset=end;}});
  return new Response(body,{headers:{'content-type':'application/vnd.android.package-archive','content-disposition':`attachment; filename="${metadata.filename}"`,'content-length':String(bytes.length),'x-checksum-sha256':metadata.sha256,'x-apk-status':'unsigned-not-installable','x-content-type-options':'nosniff','cache-control':'private, no-store, no-transform','referrer-policy':'no-referrer'}});
 }catch(error){
  return Response.json({error:{code:'UNSIGNED_ARTIFACT_UNAVAILABLE',message:'Artefak unsigned tidak tersedia pada deployment ini.',request_id:randomUUID()}},{status:(error as NodeJS.ErrnoException).code==='ENOENT'?404:503,headers:{'cache-control':'no-store'}});
 }
}
