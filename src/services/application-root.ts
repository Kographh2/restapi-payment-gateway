import path from 'node:path';
import {readFileSync} from 'node:fs';

/** Resolve a standalone checkout or the preserved monorepo entry point. */
export function applicationRoot(cwd=process.cwd()){
 for(const directory of [cwd,path.join(cwd,'web')]){
  try{if(JSON.parse(readFileSync(path.join(directory,'package.json'),'utf8')).name==='@manji/api')return directory;}
  catch{/* Try the next supported entry point without reading environment files. */}
 }
 throw Error('MANJI web application root not found');
}
