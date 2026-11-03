# Web configuration changes

## 2026-11-03 — Vercel E404 and standalone repository fix

- Included the four existing private packages in `packages/` and replaced wildcard private dependencies with repository-local `file:` references, including contracts' transitive private dependencies.
- Added a standalone npm lockfile using the existing locked external versions, build/lint/TypeScript devDependencies, local test loader and ESLint configuration, Node 24 engine selection and `vercel.json` using `npm ci`/`npm run build`.
- Corrected runtime database-root detection for arbitrary standalone paths such as Vercel's `path0`, while retaining monorepo entry points and the explicit database-root override. SQL and APK download behavior are preserved.
- Added safe environment templates, root-local tracing/Docker setup, deployment ignores and a local operator script to untrack previously committed build output, local database files and sensitive files without deleting working copies.
- Standalone resolution checks, typecheck, lint, twelve tests and optimized compilation passed. Clean npm ci remains network/cache blocked; full local builds hit spawn EPERM or experimental worker-thread DataCloneError. No full build, push, remote configuration or deployment success is claimed. See docs/VERCEL.md and IMPLEMENTATION_LOG.md.

## 2026-11-03 — Paket database lengkap di /supabase

- Centralized the web database package in `supabase/`: combined initial-install SQL, five active migrations, administrator provisioning, read-only metadata verification, empty seed, local-only Auth fixture and separately archived historical SQL.
- Default local initialization now reads the packaged SQL from `web/supabase`, including when launched from the monorepo root. The explicit `GATEWAY_REPO_ROOT` override remains supported. Existing persistent data, hosted database driver and payment authorization are unchanged.
- Moved the former root `SUPABASE_SETUP.sql` into `supabase/`, updated the exporter with a non-writing `-Check` mode, added SQL output tracing and documented installation/upgrade steps.
- Verified all eleven copied source files by SHA-256 and all five combined migration bodies/order/transactions. Four SQL integration tests from web, typecheck and lint passed. Additional monorepo-root SQL test attempts encountered native crypto/WASM runtime failures; see IMPLEMENTATION_LOG.md. No hosted migration was executed.

## 2026-11-03 — SQL Supabase di root web

- Added `SUPABASE_SETUP.sql` at the workspace root, combining the five active dated migrations in their existing order with one transaction per migration and unchanged source content.
- Documented initial-install use, existing-install migration handling and Data API schema exposure. Historical public-schema migrations, sandbox fixtures and credentials are excluded. No hosted database migration was executed.

## 2026-11-02 — Existing APK signing and download preparation

- Added an interactive local signing script using SDK zipalign/apksigner, an external durable release keystore, hidden password input, signature/fingerprint/alignment checks and byte-for-byte application payload verification. No Gradle or Android rebuild.
- Added `/aplikasi/manji-gateway-release.apk` and API alias `/api/v1/app/download`, with verification-report/checksum enforcement. The stable download fallback uses the signed URL only when verification metadata and APK are present.
- Preserved the unsigned artifact/endpoint and the existing release registry, stable/beta channels, updater, authentication and financial behavior. Added signing credential ignore rules and operator instructions in docs/APK_SIGNING.md.
- Actual signing is pending local interactive execution: runtime policy rejected an unsandboxed terminal launch. No signed APK, keystore or certificate fingerprint is claimed.

## 2026-11-02 — Production environment audit

- Added an explicit Supabase/official production template for api.manjifood.biz.id while preserving the existing local sandbox environment and database.
- Added startup/preflight validation with safe variable-name diagnostics, production HTTPS/secrets checks, Supabase public/server key mix-up rejection and optional release configuration validation.
- Documented the exact existing mode enums, Supabase migrations/Auth/hosting requirements, configuration precedence and disabled official provider gate.
- Added configuration and production callback rejection regression tests. No payment verification or database authority was relaxed. See IMPLEMENTATION_LOG.md for actual results and pending hosted checks.
