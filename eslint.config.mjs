import js from '@eslint/js';
import ts from 'typescript-eslint';
export default ts.config(js.configs.recommended, ...ts.configs.recommended, {
  files:['**/*.ts','**/*.tsx'], rules:{'@typescript-eslint/no-unused-vars':['error',{argsIgnorePattern:'^_'}]},
}, {files:['scripts/*.mjs'],languageOptions:{globals:{process:'readonly',fetch:'readonly',AbortSignal:'readonly',WebSocket:'readonly',setTimeout:'readonly',Buffer:'readonly',console:'readonly'}}}, {ignores:['**/.next/**','**/node_modules/**','**/next-env.d.ts']});
