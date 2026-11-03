# Web configuration changes

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
