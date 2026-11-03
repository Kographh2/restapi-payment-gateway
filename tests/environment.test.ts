import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ConfigurationError,validateEnvironment} from '../src/services/config';
import {register} from '../src/instrumentation';
import {MockProviderAdapter,OfficialProviderAdapter} from '../src/services/providers';
import {handle} from '../src/services/http';
import type {Database} from '../src/services/database';

const sandbox:Record<string,string|undefined> = {
  PAYMENT_ENV:'sandbox', PROVIDER_MODE:'mock', STORE_DRIVER:'pglite',
  APP_BASE_URL:'http://localhost:3000', APP_ENCRYPTION_KEY:'ab'.repeat(32),
  SANDBOX_LOGIN_SECRET:'sandbox-login-fixture-'.repeat(3), MOCK_PROVIDER_SECRET:'mock-fixture-'.repeat(4),
};
// Configuration fixtures only. No network access or successful payment fixtures.
const production:Record<string,string|undefined> = {
  PAYMENT_ENV:'production', PROVIDER_MODE:'official', STORE_DRIVER:'supabase',
  APP_BASE_URL:'https://api.manjifood.biz.id', API_BASE_URL:'https://api.manjifood.biz.id', WEBSITE_URL:'https://manjifood.biz.id',
  APP_ENCRYPTION_KEY:'cd'.repeat(32), NEXT_PUBLIC_SUPABASE_URL:'https://fixture.supabase.co',
  NEXT_PUBLIC_SUPABASE_ANON_KEY:'public-fixture-'.repeat(3), SUPABASE_SERVICE_ROLE_KEY:'private-fixture-'.repeat(3),
  OUTBOX_CRON_SECRET:'outbox-fixture-'.repeat(3),
};
function rejected(env:Record<string,string|undefined>, key:string) {
  assert.throws(() => validateEnvironment(env), (error:unknown) => error instanceof ConfigurationError && error.issues.some(issue => issue.startsWith(key + ':')));
}

test('supported environment matrix preserves sandbox and requires official Supabase production', () => {
  for (const PAYMENT_ENV of ['sandbox','production']) for (const PROVIDER_MODE of ['mock','official']) for (const STORE_DRIVER of ['pglite','supabase']) {
    const env = {...production, PAYMENT_ENV, PROVIDER_MODE, STORE_DRIVER, ...(PAYMENT_ENV === 'sandbox' ? {SANDBOX_LOGIN_SECRET:sandbox.SANDBOX_LOGIN_SECRET,MOCK_PROVIDER_SECRET:sandbox.MOCK_PROVIDER_SECRET} : {})};
    if (PAYMENT_ENV === 'sandbox' || PROVIDER_MODE === 'official' && STORE_DRIVER === 'supabase') assert.doesNotThrow(() => validateEnvironment(env));
    else assert.throws(() => validateEnvironment(env), ConfigurationError);
  }
  for (const key of ['PAYMENT_ENV','PROVIDER_MODE','STORE_DRIVER']) {
    for (const value of ['', 'live', 'gopay', 'file', 'unsupported-sensitive-value']) rejected({...sandbox,[key]:value}, key);
  }
});

test('required variables and conditional secrets fail closed with named errors', () => {
  for (const key of ['PAYMENT_ENV','PROVIDER_MODE','STORE_DRIVER','APP_BASE_URL','APP_ENCRYPTION_KEY','NEXT_PUBLIC_SUPABASE_URL','NEXT_PUBLIC_SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','OUTBOX_CRON_SECRET']) rejected({...production,[key]:undefined}, key);
  for (const key of ['SANDBOX_LOGIN_SECRET','MOCK_PROVIDER_SECRET']) rejected({...sandbox,[key]:undefined}, key);
  rejected({...production,PAYMENT_ENV:'sandbox',PROVIDER_MODE:'mock'}, 'MOCK_PROVIDER_SECRET');
  for (const value of ['short', 'AB'.repeat(32), 'xy'.repeat(32)]) rejected({...production,APP_ENCRYPTION_KEY:value}, 'APP_ENCRYPTION_KEY');
  rejected({...production,OUTBOX_CRON_SECRET:'short'}, 'OUTBOX_CRON_SECRET');
  assert.doesNotThrow(() => validateEnvironment({...production,PAYMENT_ENV:'sandbox',OUTBOX_CRON_SECRET:undefined}));
});

test('origins, production HTTPS, public keys and webhook allowlists are validated without exposing values', () => {
  for (const key of ['APP_BASE_URL','API_BASE_URL','WEBSITE_URL','NEXT_PUBLIC_SUPABASE_URL']) {
    for (const value of ['broken','http://fixture.example','https://fixture.example/path','https://user:password@fixture.example','https://fixture.example?secret=hidden','ftp://fixture.example']) rejected({...production,[key]:value}, key);
  }
  for (const WEBHOOK_ALLOWED_HOSTS of ['*','https://hooks.example.com','hooks.example.com:443','127.0.0.1','hooks.example.com,']) rejected({...production,WEBHOOK_ALLOWED_HOSTS}, 'WEBHOOK_ALLOWED_HOSTS');
  assert.doesNotThrow(() => validateEnvironment({...production,WEBHOOK_ALLOWED_HOSTS:'hooks.example.com, callbacks.example.com'}));
  rejected({...production,NEXT_PUBLIC_SUPABASE_ANON_KEY:production.SUPABASE_SERVICE_ROLE_KEY}, 'NEXT_PUBLIC_SUPABASE_ANON_KEY');
  rejected({...production,NEXT_PUBLIC_SUPABASE_ANON_KEY:'sb_secret_'+'a'.repeat(32)}, 'NEXT_PUBLIC_SUPABASE_ANON_KEY');
  rejected({...production,SUPABASE_SERVICE_ROLE_KEY:'sb_publishable_'+'b'.repeat(32)}, 'SUPABASE_SERVICE_ROLE_KEY');
  const jwt = (role:string) => 'header.'+Buffer.from(JSON.stringify({role})).toString('base64url')+'.signature-fixture';
  rejected({...production,NEXT_PUBLIC_SUPABASE_ANON_KEY:jwt('service_role')}, 'NEXT_PUBLIC_SUPABASE_ANON_KEY');
  rejected({...production,SUPABASE_SERVICE_ROLE_KEY:jwt('anon')}, 'SUPABASE_SERVICE_ROLE_KEY');
  try { validateEnvironment({...production,PROVIDER_MODE:'unsupported-sensitive-value',APP_ENCRYPTION_KEY:'secret-value'}); assert.fail('must reject'); }
  catch (error) { assert.ok(error instanceof ConfigurationError); assert.ok(!error.message.includes('unsupported-sensitive-value')); assert.ok(!error.message.includes('secret-value')); }
});

test('blank optional template values preserve development and production fails on sandbox settings', () => {
  const template = readFileSync(new URL('../.env.example', import.meta.url),'utf8');
  const values = Object.fromEntries(template.split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => { const at=line.indexOf('='); return [line.slice(0,at),line.slice(at+1)]; }));
  assert.doesNotThrow(() => validateEnvironment({...values,APP_ENCRYPTION_KEY:sandbox.APP_ENCRYPTION_KEY,SANDBOX_LOGIN_SECRET:sandbox.SANDBOX_LOGIN_SECRET,MOCK_PROVIDER_SECRET:sandbox.MOCK_PROVIDER_SECRET}));
  for (const key of ['SANDBOX_LOGIN_SECRET','MOCK_PROVIDER_SECRET','APP_RELEASE_LOCAL_DIR']) rejected({...production,[key]:'sandbox-only-'.repeat(3)}, key);
  rejected({...production,APP_RELEASE_TEST_MODE:'1'}, 'APP_RELEASE_TEST_MODE');
  rejected({...production,APP_RELEASE_BUCKET:'public-bucket'}, 'APP_RELEASE_BUCKET');
  rejected({...production,APP_RELEASE_CERT_SHA256:'aa'.repeat(32)}, 'APP_DOWNLOAD_TOKEN_SECRET');
  assert.doesNotThrow(() => validateEnvironment({...production,APP_RELEASE_CERT_SHA256:'aa'.repeat(32),APP_DOWNLOAD_TOKEN_SECRET:'download-fixture-'.repeat(3)}));
});

test('Node startup uses validation; sandbox remains distinct from NODE_ENV=production', async () => {
  const previous = process.env;
  try {
    process.env = {...sandbox,NEXT_RUNTIME:'nodejs',NODE_ENV:'production'};
    await assert.doesNotReject(register());
    process.env.PROVIDER_MODE = 'unsupported-sensitive-value';
    await assert.rejects(register(), ConfigurationError);
    const response = await handle(new Request('http://localhost:3000/health'));
    assert.equal(response.status,503);
    const body = await response.text();
    assert.ok(!body.includes('unsupported-sensitive-value'));
    assert.ok(!body.includes('PROVIDER_MODE'));
    process.env = {NEXT_RUNTIME:'edge',NODE_ENV:'test'};
    await assert.doesNotReject(register());
  } finally { process.env = previous; }
});

test('production template selects the real deployment modes and cannot pass with empty required secrets', () => {
  const template = readFileSync(new URL('../.env.production.example', import.meta.url),'utf8');
  const values = Object.fromEntries(template.split(/\r?\n/).filter(line => line && !line.startsWith('#')).map(line => { const at=line.indexOf('='); return [line.slice(0,at),line.slice(at+1)]; }));
  assert.equal(values.PAYMENT_ENV,'production');
  assert.equal(values.PROVIDER_MODE,'official');
  assert.equal(values.STORE_DRIVER,'supabase');
  assert.equal(values.APP_BASE_URL,'https://api.manjifood.biz.id');
  assert.equal(values.API_BASE_URL,'https://api.manjifood.biz.id');
  assert.throws(() => validateEnvironment(values),ConfigurationError);
  assert.doesNotThrow(() => validateEnvironment({...values,...production}));
});

test('production cannot verify mock callbacks or enable disabled official payments', async () => {
  const c = validateEnvironment(production);
  await assert.rejects(new MockProviderAdapter(c).verify('{}','forged'), {code:'NOT_FOUND'});
  await assert.rejects(new OfficialProviderAdapter().verify(), {code:'PROVIDER_NOT_ONBOARDED'});
  await assert.rejects(new OfficialProviderAdapter().createDynamic(), {code:'DYNAMIC_QRIS_UNAVAILABLE'});
  let writes = 0;
  const commands:string[] = [];
  const db:Database = {rpc:async<T>(name:string) => { commands.push(name); writes++; return {} as T; }};
  for (const prefix of ['/v1','/api/v1']) {
    for (const [route,status,code] of [['/sandbox/provider/webhook',404,'NOT_FOUND'],['/provider/webhook/official',503,'PROVIDER_NOT_ONBOARDED']] as const) {
      const response = await handle(new Request('https://api.manjifood.biz.id'+prefix+route,{method:'POST',body:'{}'}),{c,db});
      assert.equal(response.status,status);
      assert.equal((await response.json()).error.code,code);
    }
  }
  // Request audit attempts are allowed; provider_event settlement must never run.
  assert.equal(writes,4);
  assert.deepEqual(commands,Array(4).fill('worker_command'));
});
