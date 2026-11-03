import path from 'node:path';
import {readFile,stat} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import type {UnsignedArtifact} from '../types/app-artifact';

const filename='manji-gateway-release-unsigned.apk' as const;
async function artifactPath(){
 // npm -w web uses the app directory; repository-root HTTP harnesses use root/web.
 // Read the package identity instead of assuming a Vercel function directory name.
 const cwd=process.cwd(),manifest=JSON.parse(await readFile(path.join(cwd,'package.json'),'utf8'));
 return path.join(manifest.name==='@manji/api'?cwd:path.join(cwd,'web'),'aplikasi',filename);
}
export async function readUnsignedArtifact(){
 const file=await artifactPath(),info=await stat(file);
 if(!info.isFile()||info.size<1||info.size>83_886_080)throw Error('Invalid development artifact');
 const bytes=await readFile(file);if(bytes.length!==info.size)throw Error('Artifact changed during read');
 const metadata:UnsignedArtifact={filename,size_bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),unsigned:true,download_path:'/api/v1/app/unsigned/download'};
 return {bytes,metadata};
}
export async function unsignedArtifactInfo():Promise<UnsignedArtifact|null>{try{return (await readUnsignedArtifact()).metadata;}catch{return null;}}
