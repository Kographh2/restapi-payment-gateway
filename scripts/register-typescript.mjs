// In-process TypeScript transpilation for restricted Windows environments.
// tsc --noEmit remains the separate mandatory typecheck. Requires Node >=22.15.
import { registerHooks } from 'node:module';
import { readFileSync } from 'node:fs';
import { URL } from 'node:url';
import ts from 'typescript';
registerHooks({
  resolve(specifier,context,next){
    try{return next(specifier,context);}catch(error){
      if(specifier.startsWith('.')){
        for(const suffix of ['.ts','.tsx']){try{return next(specifier+suffix,context);}catch{/* Try next TypeScript extension. */}}
      }
      throw error;
    }
  },
  load(url,context,next){
    if(/\.tsx?$/.test(url)){
      const source=ts.transpileModule(readFileSync(new URL(url),'utf8'),{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ESNext,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true},fileName:new URL(url).pathname}).outputText;
      return {format:'module',source,shortCircuit:true};
    }
    return next(url,context);
  },
});
