# MANJI Gateway production environment audit

Target: `https://api.manjifood.biz.id`. Scope: the existing Next.js application, configuration and deployment checks. Existing development secrets/data are preserved. No hosted credentials, DNS change, migration or provider onboarding is implied by these files.

Milestones:

- [x] Trace supported environment values, Supabase consumers and payment authority.
- [x] Separate production template from development and enforce startup validation.
- [x] Record validation results and build limitations in [the implementation log](../IMPLEMENTATION_LOG.md).
- [ ] Operator supplies production credentials and completes hosted acceptance.

## Supported values from source

[`src/services/config.ts`](../src/services/config.ts) defines the complete enums; [`database.ts`](../src/services/database.ts), [`identity.ts`](../src/services/identity.ts), [`providers.ts`](../src/services/providers.ts) and [`http.ts`](../src/services/http.ts) implement their behavior.

| Variable | Supported values | Deployment behavior |
| --- | --- | --- |
| `PAYMENT_ENV` | `sandbox`, `production` | Explicit financial environment; independent of `NODE_ENV`. |
| `PROVIDER_MODE` | `mock`, `official` | Mock HMAC is sandbox-only. Official adapter exists but rejects verification with 503. |
| `STORE_DRIVER` | `pglite`, `supabase` | PGlite initializes a local sandbox DB. Supabase uses Auth and server-only PostgREST RPCs. There is no fallback. |

Production requires **`production` + `official` + `supabase`**. Local development uses **`sandbox` + `mock` + `pglite`**. A hosted sandbox uses **`sandbox` + `mock` + `supabase`** with its own Supabase project and mock secret. Sandbox with `official` is also accepted; the official adapter remains disabled. Neither `file`, `live`, `gopay` nor an invented provider mode is supported. The older `examples/.env.example` still describes a historical `file` driver: use the templates in `web` for this application.

## Configure production

Use [`web/.env.production.example`](../.env.production.example) as the deployment secret-manager checklist. Set:

```dotenv
PAYMENT_ENV=production
PROVIDER_MODE=official
STORE_DRIVER=supabase
APP_BASE_URL=https://api.manjifood.biz.id
API_BASE_URL=https://api.manjifood.biz.id
WEBSITE_URL=https://manjifood.biz.id
```

The dashboard and API share this Next.js deployment. `APP_BASE_URL` controls cookie security, CSRF origin and auth links; `API_BASE_URL` identifies the public API. Preserve apex/www routing for the existing food website.

| Variable | Validation / requirement |
| --- | --- |
| `PAYMENT_ENV`, `PROVIDER_MODE`, `STORE_DRIVER` | Required enums and production combination above. No implicit environment switch. |
| `APP_BASE_URL` | Required HTTP(S) origin; HTTPS in production. No credentials, path, query or fragment. |
| `API_BASE_URL` | Same origin format; HTTPS in production. Existing default is `https://api.manjifood.biz.id`. Set explicitly for deployment/development. |
| `WEBSITE_URL` | Same format; HTTPS in production. Existing default is `https://manjifood.biz.id`. |
| `APP_ENCRYPTION_KEY` | Required random 32 bytes encoded as exactly 64 lowercase hex characters. Preserve securely across deploys; rotation requires a re-encryption/revocation plan. |
| `NEXT_PUBLIC_SUPABASE_URL` | Required for Supabase; production HTTPS project origin. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Required for Supabase; public project key, at least 20 characters. Privileged key reuse/obvious role inversion is rejected. |
| `SUPABASE_SERVICE_ROLE_KEY` | Required for Supabase; server-only privileged project key, at least 30 characters. Never expose through `NEXT_PUBLIC_*`, source, Android or logs. |
| `OUTBOX_CRON_SECRET` | Required in production, at least 32 characters; independent random scheduler credential. Optional for local sandbox until cron is used. |
| `WEBHOOK_ALLOWED_HOSTS` | Optional exact lowercase DNS hostnames separated by commas. No scheme, port, wildcard or IP literal. Empty denies all outgoing webhook destinations. Public DNS/address checks remain enforced when sending. |
| `SANDBOX_LOGIN_SECRET` | At least 32 characters, required for PGlite administrator bootstrap; remove in production. |
| `MOCK_PROVIDER_SECRET` | At least 32 characters, required for `mock` with either driver and for the existing PGlite sandbox contract; remove in production. This is not a GoPay secret. |

Blank optional variables are treated as unset, so the development template can leave Supabase/distribution fields empty. Invalid supplied optional values fail validation. Validation names faulty fields without printing their contents. Key length/format and decoded legacy role checks cannot establish authenticity, project ownership or connectivity; Supabase still verifies actual requests. All Supabase values must come from the same real project.

Signed Android distribution is optional and remains disabled without its configuration. When enabled, configure **both** `APP_RELEASE_CERT_SHA256` (comma-separated real certificate fingerprints, 64 hex characters each) and `APP_DOWNLOAD_TOKEN_SECRET` (at least 32 characters). `APP_RELEASE_BUCKET`, if supplied, must be `manji-app-releases`. Publication/signing/private-bucket gates still apply. `APP_RELEASE_TEST_MODE=1` requires a loopback PGlite sandbox and `APP_RELEASE_LOCAL_DIR`; production rejects test mode and local release paths. Do not manufacture signing identities to pass checks.

`SANDBOX_DATABASE_DIR` optionally overrides the local DB path (default: `.sandbox/manji-postgres` under the process working directory). `GATEWAY_REPO_ROOT` optionally locates root migrations for local initialization. Neither changes the production driver. `NEXT_DIST_DIR`, `NEXT_WORKER_THREADS`, `PORT` and `HOSTNAME_BIND` are existing build/server controls, not payment modes or credentials.

## Supabase project setup

Follow the existing [shared-project deployment/migration guide](../../docs/deployment/MANJI.md). Gateway Android/dashboard/admin/API must share one project within an environment; keep development/staging separate from production. If production shares the existing Manji Food project, back it up and review existing triggers/schema/buckets first.

Apply only the five dated gateway migrations, in order, using a reviewed owner connection and one transaction per migration:

1. `202611020001_manji_schema.sql`
2. `202611020002_manji_commands.sql`
3. `202611020003_manji_provider_worker.sql`
4. `202611020004_manji_account_idempotency.sql`
5. `202611020005_app_distribution.sql` (review reserved private-bucket collision handling first).

Do not blindly push the historical `0001`–`0003` migrations or deploy `supabase/seed/local-auth-fixture.sql`. No SQL/schema/payment logic was changed in this audit. Add `manji_gateway` to the Data API exposed schemas; retain the migration's narrow grants and deny-by-default RLS. Do not copy generic documentation's broad `GRANT ALL` examples over these policies. Keep only the existing payment-status publication for Realtime. See [Supabase custom schema documentation](https://supabase.com/docs/guides/api/using-custom-schemas).

Enable email confirmation, production SMTP and abuse/password controls. For a dedicated gateway project, set Auth Site URL to `https://api.manjifood.biz.id`; allow `https://api.manjifood.biz.id/auth/confirm` and the existing recovery redirect `https://api.manjifood.biz.id/auth/confirm?type=recovery`. Use exact production entries, preserving other applications' required entries. For a project already shared with Manji Food, audit its current Site URL/templates before changing them: use the gateway's allowed `{{ .RedirectTo }}` in shared templates so food-site auth continues to work. A project has shared Auth settings; do not overwrite them blindly. See [Supabase redirect URL guidance](https://supabase.com/docs/guides/auth/redirect-urls).

The gateway's confirmation screen expects fragment token hashes followed by an explicit POST. Dedicated-gateway email templates:

```html
<a href="{{ .SiteURL }}/auth/confirm#token_hash={{ .TokenHash }}&type=email">Verifikasi akun MANJI</a>
<a href="{{ .SiteURL }}/auth/confirm#token_hash={{ .TokenHash }}&type=recovery">Pulihkan akun MANJI</a>
```

On a shared project, test destination-aware templates for both applications in staging; the gateway recovery redirect already includes `?type=recovery`, so append `#token_hash=...&type=recovery` to that permitted redirect rather than another `/auth/confirm`. No remote Auth/template changes were made. Provision the administrator via the existing reviewed `scripts/provision-admin.sql`, never user-editable metadata or a default production login.

## Startup and deployment validation

From `web`, with the actual deployment variables supplied securely:

```powershell
npm.cmd run check:env -- --production
npm.cmd run test:env
npm.cmd run typecheck
npm.cmd run lint
npm.cmd run build
npm.cmd start
```

From the repository root, use `npm run check:env -w web -- --production`. Retain existing root API/SQL/HTTP checks (`npm test`, `npm run test:sql`, `npm run test:http`). Preflight reads Next's environment-file precedence through `@next/env`, with process variables taking priority. `--production` selects production files and **requires `PAYMENT_ENV=production`**; it never changes a sandbox into production. A developer's existing `.env.local` can override `.env.production`; do not ship it to the host or Docker build context. Supply all deployment variables explicitly. See [Next environment loading](https://nextjs.org/docs/15/app/guides/environment-variables).

[`src/instrumentation.ts`](../src/instrumentation.ts) runs the same validation when each Node server instance starts, including direct Next/Docker starts and serverless cold starts, before serving requests. This uses [Next 15 instrumentation](https://nextjs.org/docs/15/app/api-reference/file-conventions/instrumentation). API handlers retain request-time validation and generic 503 responses. `NODE_ENV=production` also applies to optimized builds of a sandbox; it does not imply real-money mode. The explicit production preflight must be part of deployment checks.

Templates intentionally contain empty required secrets and must fail until filled. No startup check connects to Supabase or applies migrations. After provisioning, verify `/health` and `/api/health` against the actual host: expect `environment: "production"`, `auth: "Supabase Auth"`, and **`provider_enabled: false`**. Health performs a database RPC but does not prove SMTP, RLS, Realtime, release storage or provider readiness.

Point only `api.manjifood.biz.id` at this deployment, verify TLS, preserve food-site routing, and configure proxy/body/rate limits as in the existing guide. Schedule `POST /v1/internal/outbox` with `{}` and `Authorization: Bearer <OUTBOX_CRON_SECRET>` at least once per minute, or run the existing root outbox command with the same production environment. Monitor dead letters and test backup/restore, tenant isolation, login/email/reset and session/device/key revocation on the hosted project.

## Payment verification remains mandatory

Selecting `official` does not activate a real provider. `OfficialProviderAdapter.verify()` returns **503 `PROVIDER_NOT_ONBOARDED`**; dynamic QR creation remains unavailable. Production rejects the sandbox callback route; the mock adapter also independently requires sandbox + mock mode + signed, fresh events. Sandbox confirmations remain `SIMULATED_PAID`, excluded from verified revenue and fulfillment. Notifications remain untrusted evidence.

`PAID` requires the existing server-side verified-provider proof and protected transactional database checks. There is no simulation fallback, manual settlement shortcut or verification bypass. Provider credentials are not listed as invented environment variables because this source implements no live provider integration. Complete the existing provider onboarding, documented signature/status requery, replay/merchant/amount/currency/environment tests and hosted acceptance before accepting real payments.
