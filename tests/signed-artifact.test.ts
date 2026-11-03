import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {verifySignedArtifact,signedArtifactResponse} from '../src/services/signed-artifact';
import {GET,HEAD} from '../src/app/api/v1/app/download/route';
import {DownloadCenter} from '../src/components/download-center';

// Synthetic report/bytes exercise HTTP integrity checks only, never real signing.
const bytes=Buffer.from('isolated unit-test artifact; not an Android APK');
const report={schema_version:1,filename:'manji-gateway-release.apk',application_id:'id.biz.manjifood.gateway',version_code:3,version_name:'0.3.0',min_sdk:26,target_sdk:35,sha256:createHash('sha256').update(bytes).digest('hex'),size_bytes:bytes.length,signer_sha256:'ab'.repeat(32),source_sha256:'1decb2582140ac3097fcecbedca408512a07269e4bfc1fc62db36f3fffd1fd46',signature_verified:true,v2:true,v3:true,alignment_verified:true,payload_unchanged:true,unsigned_preserved:true,rebuilt:false,verified_at:'2026-11-02T00:00:00.000Z'};
test('signed artifact rejects changed bytes, failed signing evidence and a different source',()=>{
 assert.equal(verifySignedArtifact(bytes,report).download_path,'/aplikasi/manji-gateway-release.apk');
 assert.throws(()=>verifySignedArtifact(Buffer.from('changed'),report));
 for(const field of ['signature_verified','v2','v3','alignment_verified','payload_unchanged','unsigned_preserved'])assert.throws(()=>verifySignedArtifact(bytes,{...report,[field]:false}));
 assert.throws(()=>verifySignedArtifact(bytes,{...report,rebuilt:true}));
 assert.throws(()=>verifySignedArtifact(bytes,{...report,source_sha256:'00'.repeat(32)}));
});
test('signed download fails closed when absent or corrupted, and returns matching bytes and headers',async()=>{
 const previous=process.cwd(),directory=await mkdtemp(path.join(tmpdir(),'manji-signed-artifact-test-'));
 try{
  await writeFile(path.join(directory,'package.json'),JSON.stringify({name:'@manji/api'}));
  await mkdir(path.join(directory,'aplikasi'));
  process.chdir(directory);
  assert.equal((await signedArtifactResponse()).status,404);
  await writeFile(path.join(directory,'aplikasi','manji-gateway-release.verification.json'),JSON.stringify(report));
  assert.equal((await signedArtifactResponse()).status,404);
  const apk=path.join(directory,'aplikasi','manji-gateway-release.apk');
  await writeFile(apk,bytes);
  const response=await signedArtifactResponse();
  assert.equal(response.status,200);
  assert.equal(response.headers.get('content-type'),'application/vnd.android.package-archive');
  assert.equal(response.headers.get('content-disposition'),'attachment; filename="manji-gateway-release.apk"');
  assert.equal(response.headers.get('x-checksum-sha256'),report.sha256);
  assert.equal(response.headers.get('x-apk-certificate-sha256'),report.signer_sha256);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);
  const head=await signedArtifactResponse(true);assert.equal(head.status,200);assert.equal(await head.text(),'');
  await writeFile(apk,Buffer.from('tampered'));
  const corrupt=await signedArtifactResponse();assert.equal(corrupt.status,503);assert.equal((await corrupt.json()).error.code,'SIGNED_ARTIFACT_UNAVAILABLE');
  assert.equal((await signedArtifactResponse(true)).status,503);
 }finally{process.chdir(previous);await rm(directory,{recursive:true,force:true});}
});
test('API alias and website button use the signed APK canonical path',()=>{
 for(const handler of [GET,HEAD]){const response=handler();assert.equal(response.status,307);assert.equal(response.headers.get('location'),'/aplikasi/manji-gateway-release.apk');}
 const signedArtifact=verifySignedArtifact(bytes,report);
 const html=renderToStaticMarkup(createElement(DownloadCenter,{initial:null,signedArtifact}));
 assert.match(html,/href="\/aplikasi\/manji-gateway-release\.apk"/);
 assert.match(html,/download="manji-gateway-release\.apk"/);
 assert.ok(html.includes(report.signer_sha256));
 assert.ok(html.includes(report.sha256));
 const unavailable=renderToStaticMarkup(createElement(DownloadCenter,{initial:null,signedArtifact:null}));
 assert.doesNotMatch(unavailable,/href="\/aplikasi\/manji-gateway-release\.apk"/);
});
