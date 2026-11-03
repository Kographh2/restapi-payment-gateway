import path from 'node:path';
import {z} from 'zod';

// These are the existing adapter/driver values. Do not alias unknown modes.
const optional = <T extends z.ZodTypeAny>(value:T) => z.preprocess(v => v === '' ? undefined : v, value.optional());
const origin = z.string().url().refine(value => {
  try {
    const u = new URL(value);
    return ['http:', 'https:'].includes(u.protocol) && !u.username && !u.password && u.pathname === '/' && !u.search && !u.hash;
  } catch { return false; }
}, 'must be an HTTP(S) origin without credentials, path, query or fragment');
const schema = z.object({
  PAYMENT_ENV:z.enum(['sandbox','production']),
  PROVIDER_MODE:z.enum(['mock','official']),
  STORE_DRIVER:z.enum(['pglite','supabase']),
  APP_BASE_URL:origin,
  API_BASE_URL:origin.default('https://api.manjifood.biz.id'),
  WEBSITE_URL:origin.default('https://manjifood.biz.id'),
  APP_ENCRYPTION_KEY:z.string().regex(/^[a-f0-9]{64}$/),
  SANDBOX_LOGIN_SECRET:optional(z.string().min(32)),
  MOCK_PROVIDER_SECRET:optional(z.string().min(32)),
  SUPABASE_SERVICE_ROLE_KEY:optional(z.string().min(30)),
  NEXT_PUBLIC_SUPABASE_URL:optional(origin),
  NEXT_PUBLIC_SUPABASE_ANON_KEY:optional(z.string().min(20)),
  WEBHOOK_ALLOWED_HOSTS:z.string().default('').refine(value => value === '' || value.split(',').every(host => {
    const name = host.trim();
    return name.length <= 253 && name.includes('.') && name.split('.').every(label => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) && !/^\d+\.\d+\.\d+\.\d+$/.test(name);
  }), 'must contain comma-separated exact lowercase DNS hostnames, without schemes, ports or wildcards'),
  OUTBOX_CRON_SECRET:optional(z.string().min(32)),
  APP_RELEASE_CERT_SHA256:optional(z.string().refine(value => value.split(',').every(s => /^[a-f0-9]{64}$/i.test(s.trim())), 'must contain SHA-256 certificate fingerprints as 64 hex characters')),
  APP_DOWNLOAD_TOKEN_SECRET:optional(z.string().min(32)),
  APP_RELEASE_BUCKET:optional(z.literal('manji-app-releases')),
  APP_RELEASE_TEST_MODE:optional(z.enum(['0','1'])),
  APP_RELEASE_LOCAL_DIR:optional(z.string().min(1)),
});
export type Config = z.infer<typeof schema> & {dataDir:string};
export class ConfigurationError extends Error {
  constructor(public readonly issues:string[]) {
    super('Invalid gateway configuration:\n' + issues.map(issue => '- ' + issue).join('\n'));
    this.name = 'ConfigurationError';
  }
}

// Diagnostic only: decoding a legacy key is NOT signature verification or authorization.
function legacyRole(key:string|undefined):string|undefined {
  if (!key) return;
  try { return JSON.parse(Buffer.from(key.split('.')[1], 'base64url').toString()).role; } catch { return; }
}

export function validateEnvironment(env:Record<string,string|undefined>):Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    // Zod enum messages can include the supplied value. Never log raw values.
    throw new ConfigurationError(parsed.error.issues.map(issue => `${issue.path.join('.')}: ${issue.code === 'custom' ? issue.message : 'missing or invalid value'}`));
  }
  const c = parsed.data, issues:string[] = [];
  const requireValue = (key:keyof typeof c, reason:string) => { if (!c[key]) issues.push(`${key}: ${reason}`); };
  if (c.PAYMENT_ENV === 'production') {
    if (c.STORE_DRIVER !== 'supabase') issues.push('STORE_DRIVER: production requires supabase');
    if (c.PROVIDER_MODE !== 'official') issues.push('PROVIDER_MODE: production requires official; mock payments are forbidden');
    for (const key of ['APP_BASE_URL','API_BASE_URL','WEBSITE_URL'] as const) {
      if (new URL(c[key]).protocol !== 'https:') issues.push(`${key}: production requires HTTPS`);
    }
    requireValue('OUTBOX_CRON_SECRET', 'required for the production outbox scheduler (at least 32 characters)');
    for (const key of ['SANDBOX_LOGIN_SECRET','MOCK_PROVIDER_SECRET','APP_RELEASE_LOCAL_DIR'] as const) {
      if (c[key]) issues.push(`${key}: remove sandbox-only configuration from production`);
    }
    if (c.APP_RELEASE_TEST_MODE === '1') issues.push('APP_RELEASE_TEST_MODE: test distribution is forbidden in production');
  }
  if (c.STORE_DRIVER === 'supabase') {
    for (const key of ['SUPABASE_SERVICE_ROLE_KEY','NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY'] as const) requireValue(key, 'required for supabase');
    if (c.PAYMENT_ENV === 'production' && c.NEXT_PUBLIC_SUPABASE_URL && new URL(c.NEXT_PUBLIC_SUPABASE_URL).protocol !== 'https:') issues.push('NEXT_PUBLIC_SUPABASE_URL: production requires HTTPS');
    if (c.NEXT_PUBLIC_SUPABASE_ANON_KEY && (c.NEXT_PUBLIC_SUPABASE_ANON_KEY.startsWith('sb_secret_') || legacyRole(c.NEXT_PUBLIC_SUPABASE_ANON_KEY) === 'service_role' || c.NEXT_PUBLIC_SUPABASE_ANON_KEY === c.SUPABASE_SERVICE_ROLE_KEY)) issues.push('NEXT_PUBLIC_SUPABASE_ANON_KEY: must be a public key, never the privileged server key');
    if (c.SUPABASE_SERVICE_ROLE_KEY && (c.SUPABASE_SERVICE_ROLE_KEY.startsWith('sb_publishable_') || legacyRole(c.SUPABASE_SERVICE_ROLE_KEY) === 'anon')) issues.push('SUPABASE_SERVICE_ROLE_KEY: must be the privileged server key');
  }
  if (c.STORE_DRIVER === 'pglite') {
    if (c.PAYMENT_ENV !== 'sandbox') issues.push('PAYMENT_ENV: pglite is sandbox only');
    requireValue('SANDBOX_LOGIN_SECRET', 'required for local sandbox administrator login (at least 32 characters)');
    requireValue('MOCK_PROVIDER_SECRET', 'required for pglite sandbox (at least 32 characters)');
  }
  if (c.PROVIDER_MODE === 'mock') requireValue('MOCK_PROVIDER_SECRET', 'required for mock provider verification (at least 32 characters)');
  // Signed Android distribution stays optional; partial configuration is an error.
  if (c.APP_RELEASE_CERT_SHA256 || c.APP_DOWNLOAD_TOKEN_SECRET) {
    requireValue('APP_RELEASE_CERT_SHA256', 'required when signed Android distribution is configured');
    requireValue('APP_DOWNLOAD_TOKEN_SECRET', 'required when signed Android distribution is configured');
  }
  if (c.APP_RELEASE_TEST_MODE === '1') {
    if (c.PAYMENT_ENV !== 'sandbox' || c.STORE_DRIVER !== 'pglite' || !['localhost','127.0.0.1'].includes(new URL(c.APP_BASE_URL).hostname)) issues.push('APP_RELEASE_TEST_MODE: requires a loopback pglite sandbox');
    requireValue('APP_RELEASE_LOCAL_DIR', 'required for test distribution');
  }
  if (issues.length) throw new ConfigurationError(issues);
  return {...c, dataDir:env.SANDBOX_DATABASE_DIR || path.resolve(process.cwd(), '.sandbox/manji-postgres')};
}

export function config():Config { return validateEnvironment(process.env); }
