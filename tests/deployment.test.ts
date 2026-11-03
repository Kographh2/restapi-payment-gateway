import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtemp,mkdir,writeFile,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {applicationRoot} from '../src/services/application-root';

test('database root resolves a standalone Vercel path and the original monorepo layout',async()=>{
 const directory=await mkdtemp(path.join(tmpdir(),'manji-deployment-path-'));
 try{
  const standalone=path.join(directory,'path0');await mkdir(standalone);
  await writeFile(path.join(standalone,'package.json'),JSON.stringify({name:'@manji/api'}));
  assert.equal(applicationRoot(standalone),standalone);
  const repo=path.join(directory,'monorepo'),web=path.join(repo,'web');await mkdir(web,{recursive:true});
  await writeFile(path.join(repo,'package.json'),JSON.stringify({name:'manji-gateway'}));
  await writeFile(path.join(web,'package.json'),JSON.stringify({name:'@manji/api'}));
  assert.equal(applicationRoot(repo),web);assert.equal(applicationRoot(web),web);
  assert.throws(()=>applicationRoot(directory),/root not found/);
 }finally{await rm(directory,{recursive:true,force:true});}
});

test('all private package dependencies and exports stay inside the standalone repository',async()=>{
 const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
 const manifest=JSON.parse(await readFile(path.join(root,'package.json'),'utf8'));
 const lock=JSON.parse(await readFile(path.join(root,'package-lock.json'),'utf8'));
 assert.deepEqual(lock.packages[''].dependencies,manifest.dependencies);
 assert.deepEqual(lock.packages[''].devDependencies,manifest.devDependencies);
 for(const [name,specifier]of Object.entries(manifest.dependencies) as [string,string][]){
  if(!name.startsWith('@manji/')&&!name.startsWith('@merchant/'))continue;
  assert.ok(specifier.startsWith('file:./packages/'),name+' must resolve locally');
  const directory=path.resolve(root,specifier.slice(5));assert.ok(directory.startsWith(root+path.sep));
  const locked=lock.packages['node_modules/'+name];assert.equal(locked.link,true);
  assert.equal(path.resolve(root,locked.resolved),directory);
  const local=JSON.parse(await readFile(path.join(directory,'package.json'),'utf8'));assert.equal(local.name,name);
  const exports=typeof local.exports==='string'?[local.exports]:Object.values(local.exports) as string[];
  for(const entry of exports)assert.ok((await readFile(path.resolve(directory,entry))).length>0);
  for(const [dependency,value]of Object.entries(local.dependencies??{}) as [string,string][]){
   if(!dependency.startsWith('@manji/'))continue;
   assert.ok(value.startsWith('file:'));
   const target=path.resolve(directory,value.slice(5));assert.ok(target.startsWith(root+path.sep));
   assert.equal(JSON.parse(await readFile(path.join(target,'package.json'),'utf8')).name,dependency);
  }
 }
});
