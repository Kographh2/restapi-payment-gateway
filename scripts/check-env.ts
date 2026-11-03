import path from 'node:path';
import {fileURLToPath} from 'node:url';
import nextEnv from '@next/env';
import {ConfigurationError,validateEnvironment} from '../src/services/config';

try {
  if (process.argv.slice(2).some(arg => arg !== '--production')) throw new Error('Usage: npm run check:env -- [--production]');
  const production = process.argv.includes('--production');
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  // Same file precedence as Next. Deployment env overrides local files.
  nextEnv.loadEnvConfig(root, !production && process.env.NODE_ENV !== 'production', {info:()=>{},error:()=>{throw new Error('Could not load environment files');}});
  const c = validateEnvironment(process.env);
  if (production && c.PAYMENT_ENV !== 'production') throw new ConfigurationError(['PAYMENT_ENV: --production requires production; local sandbox configuration cannot pass deployment preflight']);
  console.log(`Environment valid: PAYMENT_ENV=${c.PAYMENT_ENV}, PROVIDER_MODE=${c.PROVIDER_MODE}, STORE_DRIVER=${c.STORE_DRIVER}`);
  if (c.PAYMENT_ENV === 'production') console.log('Configuration validation only. Supabase connectivity/migrations are not checked. Official provider remains disabled; no verified payment readiness is asserted.');
} catch (error) {
  console.error(error instanceof ConfigurationError ? error.message : 'Environment preflight failed. Check the command and environment file access.');
  process.exitCode = 1;
}
