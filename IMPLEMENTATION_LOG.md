# Production environment audit — 2026-11-02

## SQL Supabase di root workspace — 2026-11-03

- [x] Located the five active `20261102*.sql` migrations from `src/services/database.ts` and the current deployment guide; excluded historical migrations and the local auth fixture.
- [x] Created `web/SUPABASE_SETUP.sql` at the writable workspace root. The monorepo root is outside this session's writable filesystem scope; canonical migration files remain at `supabase/migrations` in that parent repository.
- [x] Verified every embedded migration matches its original content exactly, appears in the expected order and has a separate BEGIN/COMMIT transaction. Included per-source SHA-256 comments and initial-install instructions.
- [x] Added the root SQL link and execution instructions to web/README.md. No application behavior, source migrations, credentials, Android build or APK was changed by this SQL packaging task.
- [ ] Hosted Supabase execution was not performed. The combined file is for a new gateway schema; existing installations must apply only missing original migrations. Expose `manji_gateway` in Supabase Data API settings after installation.

## Existing APK signing request — 2026-11-02 (pending interactive execution)

The user requested signing the existing APK, an external durable keystore with interactive password entry, and signed website/API downloads, without Gradle or rebuilding Android. Root instructions and the existing distribution paths were inspected. No existing release keystore was found in the inspected conventional locations; the Android debug key was excluded.

- [x] Audited source: `aplikasi/manji-gateway-release-unsigned.apk`, 8,293,976 bytes; SHA-256 `1decb2582140ac3097fcecbedca408512a07269e4bfc1fc62db36f3fffd1fd46`; package `id.biz.manjifood.gateway`, version 0.3.0/code 3, min SDK 26/target SDK 35. SDK apksigner correctly rejects its missing signature.
- [x] Located SDK build-tools 35.0.0 and JDK 17. SDK zipalign processed a separate disposable APK; `zipalign -c -P 16 4` returned exit 0. The disposable file was removed using a non-forced, explicit-path cleanup. The original unsigned APK SHA-256 was rechecked and is unchanged.
- [x] Prepared `scripts/sign-existing-apk.ps1`: local hidden password/confirmation, external PKCS12/RSA-4096 keystore and restricted Windows ACLs, source/manifest validation, SDK alignment/signing/verification, certificate fingerprint extraction, full original ZIP-entry payload comparison, original preservation and non-secret verification report. Refuses overwriting signed output or existing keystore. PowerShell parser reports no syntax errors.
- [x] Prepared canonical Node download route `/aplikasi/manji-gateway-release.apk`, API redirect `/api/v1/app/download`, guarded stable download fallback and fingerprint/checksum display. Missing signed output/report returns 404; changed bytes or failed evidence returns 503. Output tracing includes signed APK and report. Original unsigned route and protected release catalog/updater are unchanged.
- [x] Web TypeScript check and lint passed. Three targeted tests passed: altered artifact/evidence rejection; isolated download/HEAD/error handling and matching bytes/headers; canonical API and rendered website links/checksum/fingerprint with truthful missing-artifact state. These synthetic fixtures are isolated tests and do not establish real APK signing.
- [x] Existing environment/security configuration suite executed: 5/7 passed. Two failures concern configuration files untouched by this task: missing `.env.example`, and the production template enables distribution settings without a matching `APP_RELEASE_CERT_SHA256` in its test setup. These failures are recorded without changing unrelated configuration. No Gradle, Android build, deployment, database mutation or credential commit occurred.
- [ ] Actual keystore generation and signing: after the user explicitly authorized running without sandbox, an unsandboxed interactive PowerShell launch was attempted. The runtime rejected it immediately: `sandbox_approval: false`; no process was launched. A permanent external signing key cannot be written by this sandbox, and no password has been supplied through a local interactive terminal. The operator must run the prepared script locally (see docs/APK_SIGNING.md) or change the runtime permission profile.
- [ ] `aplikasi/manji-gateway-release.apk`, actual signature verification and certificate SHA-256 fingerprint remain pending. No signed output or fingerprint is fabricated. No physical-device or hosted-download success is claimed.

A subsequent parallel verification attempt hit PowerShell `System.OutOfMemoryException` after the alignment check and Node native heap allocation failure before executing tests. Final targeted tests (3/3), typecheck and lint then passed sequentially with Node `--max-old-space-size=256 --max-semi-space-size=1`. The two environment-template test failures above remain unresolved and are outside this signing/download change.

The production environment audit below predates this signing task and remains preserved.

Scope: existing MANJI Gateway web application at api.manjifood.biz.id. Root AGENTS.md, numbered specification documents, current deployment/security/database/API guides, schema, API examples and runtime consumers were reviewed. The parent repository is readable; this task's writable workspace is `web`, so this update's documentation, changelog, test suite and log live here and are linked from web/README.md. Historical root documentation remains unchanged.

- [x] Confirmed source-supported enums: PAYMENT_ENV=sandbox|production, PROVIDER_MODE=mock|official, STORE_DRIVER=pglite|supabase.
- [x] Preserved development .env.local and existing sandbox data; no sandbox setup, credential rotation, remote migration or deployment performed.
- [x] Added production template, safe startup/preflight validation and deployment guide with conditional variable requirements.
- [x] Kept official adapter disabled and mock callbacks sandbox-only; no successful production payment was simulated.
- [x] Record tests, typecheck/lint, compiled startup-hook validation and full-build limitation below.
- [ ] Hosted Supabase credentials, migration/RLS/Auth/SMTP/Realtime, DNS/TLS, scheduler and provider acceptance remain operator deployment gates.

No real production Supabase credentials or project selection were supplied by this task. The production template deliberately leaves required secrets empty. Configuration preflight validates shape and combinations only; it cannot establish hosted connectivity or enable payment verification.

## Changes and audit findings

The existing production combination was already official + Supabase, and both runtime provider adapters and SQL protect payment authority. Gaps addressed: errors named no fields; validation ran on requests rather than server startup; a Supabase mock sandbox could omit its verification secret; production could omit its scheduler secret; blank optional values in the existing example failed schema parsing. The new validator preserves exact enum values and existing API/storage/auth architecture, adds HTTPS/origin checks and public/server key mix-up detection, rejects sandbox/test settings in production, and checks optional signed-release configuration when supplied. No provider adapter, payment handler or SQL/migration file was changed.

`src/instrumentation.ts` invokes the shared validator at Node startup. `npm run check:env -- --production` uses Next environment loading and refuses a sandbox. `NODE_ENV=production` remains compatible with optimized sandbox execution; explicit PAYMENT_ENV controls financial behavior. The production guide documents the separate deployment preflight requirement, all required/conditional variables, historical unsupported file driver, shared-project compatibility, existing five migrations, Auth/email redirects and outstanding hosted gates.

## Actual validation

Final commands ran from `web` unless noted. For resource-constrained commands, `NODE_OPTIONS=--max-old-space-size=768 --max-semi-space-size=4` was set only in that command's process environment.

| Check | Result |
| --- | --- |
| `npm run test:env` | **7 passed**, zero failures/skips: exact supported matrix; required secrets; HTTPS/origins/allowlists; public/server key mix-ups and value redaction; blank optional values; production/test separation; source startup-hook rejection and generic API 503; production template; both callback aliases reject production simulation. |
| `npm run typecheck` | **Passed**, including the added scripts/tests. An initial test-only ProcessEnv typing error was corrected before the final run. |
| `npm run lint` | **Passed**, zero warnings, including src/scripts/tests. |
| `npm run check:env` | **Passed** on the existing local environment: sandbox/mock/pglite. No secret values printed. |
| `npm run check:env -- --production` | **Expected rejection**, exit 1: existing PAYMENT_ENV=sandbox cannot pass production preflight. No local configuration overwritten. |
| Existing root API/security/SQL regression tests | **16 passed** when run individually in fresh processes, zero failed/skipped cases in the final isolation run. Root working directory is required for the existing SQL storage fixture. |
| Compiled `.next/server/instrumentation.js` register hook | **Passed**: injecting an unsupported PAYMENT_ENV causes ConfigurationError mentioning the field without printing the supplied value. This verifies the compiled hook, not a full server deployment. |
| Full optimized Next build | **Blocked by this environment**: webpack compiles successfully, then the lint/type worker fails with spawn EPERM; enabling the existing NEXT_WORKER_THREADS option instead fails with native V8 memory allocation errors. No full build success is claimed. |
| Hosted Supabase/provider/SMTP/DNS/TLS | **Not performed**. Production project credentials were not supplied. |

The final existing-test run selected each of the 16 top-level test names in `tests/manji/*.test.ts` and `tests/manji/sql/*.test.ts` from the monorepo root, using the existing loader and `--test --experimental-test-isolation=none --test-name-pattern <exact escaped name>`. Node flags were `--liftoff-only --no-wasm-tier-up --wasm-num-compilation-tasks=1`, with the bounded NODE_OPTIONS above. These flags constrain PostgreSQL/PGlite's WebAssembly compilation for local verification; no product runtime or database fixture was changed. The final counter was `isolated_tests=16 failures=0`.

Earlier unbounded checks hit V8 memory allocation errors. Combined PGlite runs also produced intermittent WASM initialization `RuntimeError: unreachable`; the first run from web additionally revealed the existing SQL storage test's root-relative fixture path. Those combined attempts are failures, superseded only for test coverage by the final individually passing run. Full build retries with worker threads and bounded heap/semi-space still failed; typecheck and lint passed separately without disabling any build gate. The production HTTP harness was not rerun against an incomplete build.

## Delivery checklist

- [x] Development environment and persistent sandbox configuration preserved; production template contains no fabricated project keys.
- [x] Exact existing values documented and validated; no invented provider mode or storage fallback.
- [x] Production mock rejection and disabled official provider verified; no real-money successful payment simulation, verification bypass, Android build/signing or remote mutation.
- [x] Development and production template, README/deployment guide, local changelog and this validation log updated within the authorized web workspace.
- [ ] Full Next build on a host with working worker/resource support, followed by existing HTTP regression checks.
- [ ] Operator-selected production Supabase credentials, reviewed migrations/Auth/Realtime/RLS/storage acceptance, SMTP, DNS/TLS, scheduler and backup/restore verification.
- [ ] Approved real provider adapter with documented authenticated verification/requery and settlement/replay/refund tests before accepting money.
