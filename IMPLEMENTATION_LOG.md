# Production environment audit — 2026-11-02

## Production registration 503 — 2026-11-03

Confirmed failure and trace:

- Direct live probes returned `503 DATABASE_UNAVAILABLE` for GET `https://api.manjifood.biz.id/health` and POST `/v1/auth/register` with body `{}`. The deliberately invalid registration probe cannot create an account or send email. Initial request IDs: `28d84eac-3d62-4b97-8cb0-264ca38a58dc` and `317b4c81-aa18-4b02-92d1-a1382ae0aa72`.
- A separate read-only RPC using the local production Supabase configuration returned **HTTP 406 / PGRST106** for `schema('manji_gateway').rpc('account_command', {p_command:'public.configuration',...})`. The configured APP_BASE_URL matches the deployed production origin. Configuration validation passed; credential values, project URL, upstream message/details/hint and private data were not output. This proves the configured project's custom-schema selection is rejected by PostgREST. Private Vercel environment settings/logs themselves were not accessed, so no independent claim that every deployed variable matches the local file is made.
- Registration performs the database `rate` RPC before parsing the input and the `public.configuration` RPC before calling Supabase Auth. Both target the rejected schema. The adapter previously discarded PostgREST status/code and translated every unrecognized database error to the generic UI message. No provider adapter is invoked by registration or merchant review. The provider-onboarding warning was a startup capability notice, not an authentication gate.
- The required production correction is **adding manji_gateway to Supabase Data API Exposed schemas**, preserving all current entries. An existing explicit authenticator override may need the supplied guarded owner SQL instead. This is an external project configuration repair; changing UI error text, falling back to public schema, skipping RPC/rate checks, enabling mock or bypassing RLS would not fix it safely.

Changed files for this task:

- `src/services/diagnostics.ts`: explicit structured log fields and AsyncLocalStorage request correlation; no raw Error/request/stack/body/URL/header serialization.
- `src/services/database-failure.ts` and `database.ts`: distinguish schema exposure, missing/stale RPC, missing migration, denied database permission, rejected server credential and transport failures, retaining safe client errors and real SQL business/role/rate exceptions.
- `src/services/http.ts`: request IDs and sanitized operation context cover configuration, database, provider and HTTP failures; already-diagnosed dependency errors are not duplicated. Request audit failures remain separately identified by RPC/command with the same correlation ID.
- `src/services/identity.ts`: log signup errors under Supabase Auth, distinguish Auth infrastructure failures from rejected input, preserve email-confirmation/PENDING behavior and registration configuration checks; no signup retry or default grant.
- `src/instrumentation.ts`: fail-closed configuration errors get safe field-name logs; disabled payment capability becomes one informational event per process, loaded only on the Node runtime. No provider verification was enabled.
- `scripts/check-database.ts` and package scripts: read-only configured RPC test, optional live health/invalid-registration probes, and targeted registration tests. No secret or environment value is printed.
- `supabase/scripts/expose-manji-schema.sql`: concrete owner repair preserving an existing role/database-specific allowlist, appending only manji_gateway and reloading PostgREST. It refuses to guess an unavailable allowlist and changes no table/function grants or RLS. `verify.sql` now also checks the RPC signatures, signup trigger and only the schema-allowlist role setting.
- `tests/registration.test.ts`, `tests/registration-sql.test.ts`, `docs/REGISTRATION.md`, Supabase/root README, CHANGELOG and this record.

Actual validation:

| Check | Result |
| --- | --- |
| Real Supabase SDK with isolated fixture transport | Eight tests passed: production official-mode registration 202/PENDING on both API aliases; custom-schema/service-key RPC and anon-key Auth separation; exact PGRST106 reproduction before signup; missing RPC/migration, permissions, credentials and network classification; rate/role/closed-registration enforcement; Auth 500/422/429 distinction; health independent of provider; concurrent correlation and startup informational event. These are transport fixtures, not hosted signup claims. |
| Existing environment/deployment/download tests | Twelve tests passed, zero failures/skips. Together with the above: 20 lightweight tests passed in one run. |
| PostgreSQL registration/merchant workflow + repair | One test passed using real PGlite/PostgreSQL and all five dated migrations: editable ADMIN metadata remains PENDING; only authorized admin review approves merchant; provider remains disabled; RLS/privileged RPC denial survives the repair; existing exposed schemas preserved, repeat execution idempotent, unknown allowlist rejected. |
| Existing cross-tenant SQL/RLS regression | One test passed. |
| Existing immutable verification/settlement/refund regression | One test passed; no real provider access implied by its owned SQL fixture. |
| Total local tests | **23 passed**, no skips in the final runs. |
| TypeScript / ESLint | Passed, zero lint warnings. Initial test-only generic typing and an unnecessary default Supabase schema generic mismatch were corrected before the passing final checks. |
| SQL bundle integrity | Passed; all five active migration bodies/order/transactions remain unchanged. No RLS migration was weakened or rewritten. |
| Real configured database connectivity | **Still fails: 406/PGRST106** until the external schema setting is repaired. This is the confirmed production-configuration blocker, not a passing connectivity test. |
| Final live endpoint recheck | **Still 503**, as detailed below. Not reported fixed. |

Last recheck: diagnostic event timestamp **2026-11-03 04:02:18 UTC**. The configured Supabase RPC still reported PGRST106/406. Live GET `/health` returned 503, request ID `0641da1c-7931-4435-bc44-702b13e72c61`; live POST `/v1/auth/register` with invalid body returned 503, request ID `f28c585d-08c7-4a4b-b7a7-8544cddb86fe`.

Access limitation and outstanding production action: no owner PostgreSQL connection, Supabase project-settings connector or management credential is available in this session. Service-role REST access cannot edit project API exposure settings. The operator was asked to add the schema (or execute the tested owner repair) and confirm, after which the real RPC/endpoints can be checked again. No remote configuration/migration, account creation, email, credential rotation, commit, push or deployment was performed. UI, production mock rejection, official provider-disabled behavior, RLS and payment authority remain intact. The earlier curl/proxy failures were superseded by the successful native-fetch probes above; production unavailability is not inferred solely from a local network error.

## Vercel install E404 — 2026-11-03

Observed remote failure: Vercel cloned `restapi-payment-gateway` at `55eb371`, then npm tried to fetch `@manji/contracts@*` from the public registry and returned 404. Read-only Git inspection confirmed this is now a separate Git repository rooted directly at `web`: the commit includes src/package.json but none of the parent monorepo's packages, root manifest/lockfile, loader, TypeScript devDependencies or ESLint config. The initial monorepo deployment instructions therefore did not match the uploaded repository.

Completed changes:

- Included the existing contracts, validation, shared-types and legacy shared packages under `packages/`. Their TypeScript payloads are copied unchanged; private dependency manifests use local `file:` references rather than registry wildcards.
- Added package-local devDependencies and direct `@next/env`, local loader/ESLint configuration, Node 24.x, `package-lock.json`, and Vercel `npm ci`/`npm run build` settings. The lockfile was seeded from the existing monorepo lock and normalized successfully with an offline package-lock-only npm install; locked external versions match the installed/reference versions, with no intended library upgrade.
- Made Next file tracing and TypeScript package includes repository-local. Runtime database-root detection now checks the app package identity rather than requiring the directory basename `web`, preserving explicit GATEWAY_REPO_ROOT and original monorepo entry points.
- Added safe development/production environment templates that were absent from the Git source, keeping all real .env/key files untouched. Updated standalone Docker configuration and deployment/readme instructions. All production validation, provider-disabled behavior, payment authority, SQL and existing signed/unsigned routes remain enforced.
- Added Git/Vercel/Docker ignore rules. Read-only Git inspection found .next variants, .sandbox, .env, key.txt and tsconfig.tsbuildinfo already tracked; ignore rules alone cannot remove them from existing commits. Prepared `scripts/untrack-local-files.ps1` to remove only their index entries while preserving local files. The session provides .git as read-only, so this operator script was not executed; no staging, commit, push, history rewrite, credential access/rotation, Vercel configuration change or remote deployment occurred.

Validation and boundaries:

| Check | Result |
| --- | --- |
| Private dependencies and lockfile | Passed: direct and transitive private dependencies resolve to local package files, the lock root matches package.json and all exports exist within this repository. |
| Isolated npm ci --dry-run --offline | Passed against a fresh source copy with its own package.json/packages/lockfile; no private registry lookup was required. This is not a successful full install. |
| Real isolated npm ci | Blocked by external package downloads: initial ENOTCACHED, online attempt ECONNREFUSED 127.0.0.1:9, and another offline attempt ENOTCACHED. Copying 120 exact cached registry tarballs from the existing user cache into the workspace cache still left missing required tarballs. No false npm-ci success is claimed. |
| Build-only isolated dependency fallback | Copied 143 available packages from the existing installed tree after checking their versions against the lockfile. This does not establish fresh registry-download/integrity verification. All 19 direct production/development dependencies resolve within the isolated checkout, including private package junctions that point inside that checkout. |
| Isolated source checks | TypeScript and ESLint passed using only that isolated tree. Twelve deployment/environment/download tests passed with zero failures/skips. A first 256 MB typecheck hit its heap limit; the final explicit typecheck passed at 512 MB. A separate test attempt hit ENOSPC in the system temp directory; the final isolated tests passed with process-scoped TEMP/TMP pointing to ignored workspace scratch space. |
| Optimized standalone compilation | Passed with Next 15.5.28 and no unresolved private-package imports. Source copy excluded the real .env, key.txt, .sandbox, .next and parent sources. Build environment used explicit synthetic local sandbox fixtures only. |
| Full default build | Failed after successful compilation at lint/type worker startup: spawn EPERM. It is not reported as a successful build. |
| Existing worker-thread build option | Compilation, lint and type validation passed; it then failed during static generation with DataCloneError: ()=>null could not be cloned. This alternate build is also not reported as successful. No lint/type gate or application feature was disabled. |
| SQL package -Check | Passed: five original migration bodies/order/transactions are unchanged. No hosted migration was executed. |
| Diff whitespace | git diff --check passed. Existing CRLF conversion notices are not code failures. |
| Hosted Vercel/Supabase/installer acceptance | Not performed. The operator must commit the complete source, local packages, lockfile, Supabase package and Vercel settings, clean previously tracked local files, then redeploy from the repository root/default directory. |

The complete source changes are reviewable locally. `docs/VERCEL.md` records Root Directory default/`.` for this standalone GitHub repository, Node 24.x, `npm ci`, `npm run build`, environment configuration, source cleanup and the difference from deploying the original parent monorepo. Ignored `.deployment-check/` and `.npm-cache/` contain local validation artifacts only and must not be committed or uploaded. No Android build or Gradle command was run.

## Paket database lengkap di /supabase — 2026-11-03

Request: include the complete application's SQL under `/supabase`. This session's workspace root is `web`, so the resulting self-contained database package is `web/supabase`. The parent monorepo's source files are preserved; this operation does not export or migrate live user data.

- [x] Included five active migrations, covering the 23 application table definitions, functions/RPCs, constraints/indexes/triggers, RLS/grants, payment authority, Realtime publication, webhook worker and private Android release catalog/storage.
- [x] Moved the combined initial-install bundle from `web/SUPABASE_SETUP.sql` to `web/supabase/SUPABASE_SETUP.sql`. It includes only the active migrations, in order, with one transaction per migration and original source SHA-256 comments.
- [x] Included existing `seed.sql`, the explicitly local-only Auth fixture and protected psql administrator provisioning script. Placed the three historical public-schema migrations in `supabase/archive/legacy-public`, outside active migrations and the combined bundle. All eleven copied SQL source files match their parent originals by SHA-256.
- [x] Added Indonesian installation/upgrade/admin/local/archive instructions and a read-only `supabase/scripts/verify.sql` for hosted metadata checks. Updated README/deployment references and the exporter with a non-writing `-Check` mode.
- [x] Default local runtime now reads package-local migrations/fixture from `web/supabase`; an explicit `GATEWAY_REPO_ROOT` remains a supported override. Persistent database locations, environments, hosted Supabase driver and existing business rules were not changed. Next file tracing includes the required local migration/fixture files.

Actual validation from `web`:

| Check | Result |
| --- | --- |
| Export script `-Check` | Passed: all five bundled source bodies match, correct order, five separate BEGIN/COMMIT pairs. |
| Eleven source copy SHA-256 comparisons | Passed: five active migrations, three historical migrations, seed, Auth fixture and admin provisioning. |
| Existing SQL migration/registration test | Passed with the new default package-local path. |
| Existing SQL tenant isolation/RLS test | Passed: cross-tenant reads/writes, secret access and privileged RPC denial. |
| Existing SQL settlement/refund test | Passed: immutable matching verification is required for privileged state transitions. |
| Existing SQL distribution-storage test | Passed from web using `web/supabase`: direct bucket access denied despite broad older policies; unrelated existing bucket unchanged. |
| TypeScript and ESLint | Passed with zero lint warnings. |
| Additional monorepo-root migration test | Two attempts failed: first native scrypt `Deriving bits failed` after the migrations loaded, then PGlite/WASM `RuntimeError: unreachable` during initdb. These attempts are not claimed as passing. The four completed web SQL tests above remain the actual passing integration evidence. |
| Hosted Supabase and deployment tracing artifacts | Not executed/verified. `verify.sql` is prepared for operator use on the hosted project; no live acceptance is claimed. |

Checks ran sequentially to limit Windows resource pressure. SQL tests used Node `--max-old-space-size=384 --max-semi-space-size=1 --liftoff-only --no-wasm-tier-up --wasm-num-compilation-tasks=1` and the existing TypeScript loader; typecheck/lint used a 256 MB old-space limit. The root retry used 256 MB and encountered the separately recorded WASM initialization failure. No cryptographic check, RLS policy, payment guard or hosted release gate was weakened to make a test pass. No Gradle, Android rebuild, credential commit, local data reset or remote database mutation occurred.

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
