# MANJI Gateway web application

Semua SQL database tersedia di [supabase/](supabase/README.md): [SUPABASE_SETUP.sql](supabase/SUPABASE_SETUP.sql), lima migrasi aktif, provisioning admin, pemeriksaan metadata, seed lokal dan arsip historis yang dipisahkan. Paket instalasi gabungan memuat kelima migrasi aktif sesuai urutan tanpa mengubah isinya. Jalankan paket tersebut melalui SQL Editor sebagai owner/postgres hanya untuk instalasi awal; jika schema sudah dipasang sebagian, jalankan hanya migrasi lanjutan yang belum diterapkan. Tambahkan `manji_gateway` ke Exposed schemas pada pengaturan Data API setelah instalasi. Fixture auth lokal dan arsip historis tidak masuk paket instalasi hosted. Belum ada eksekusi pada Supabase hosted.

This repository is deployable on its own. Run `npm ci` from this directory, configure your local environment using `.env.example`, then run `npm run dev`. Build with `npm run build` and `npm start` on a host supporting worker processes. Production configuration uses `.env.production.example` as a secret-manager checklist; no environment fallback is enabled.

This directory contains the existing Next.js application and the former dashboard UI package. Pages are under `src/app`, UI/styles under `src/components`, browser API/realtime helpers under `src/lib`, and backend modules under `src/services`. Shared contracts/validation/types are included in `packages/` and resolved through local `file:` dependencies. The database package and default local runtime migration sources are in `supabase/`. No build file depends on the former parent monorepo being present.

Validation from this repository root is `npm run typecheck`, `npm run lint`, `npm run test:deployment`, `npm run test:env` and `npm run build`. Existing local environment files and persistent sandbox data are preserved. Do not run sandbox setup over existing configuration.

Route groups organize login/registration and administrator/merchant pages without changing `/login`, `/register`, `/account`, `/auth/confirm` or `/admin`. `/merchant` hosts the existing merchant page and `/dashboard` preserves its former URL. Canonical `/v1/*`, compatible `/api/v1/*`, `/health`, new `/api/health`, `/docs` and `/openapi.json` remain on `https://api.manjifood.biz.id`.

## Sign the existing APK without rebuilding

See [local interactive signing and verification](docs/APK_SIGNING.md). The prepared script uses Android SDK zipalign/apksigner and stores a new password-protected release key outside the repository. The signed file target is `aplikasi/manji-gateway-release.apk`; the website uses `/aplikasi/manji-gateway-release.apk`, and `/api/v1/app/download` redirects there. Both the signed APK and its verification report must be present and match before this download is enabled. The existing unsigned file and release catalog remain available independently. Actual signing currently awaits local password entry because the Codex runtime rejected an unsandboxed launch; no signed APK is claimed yet.

## Existing unsigned APK

`aplikasi/manji-gateway-release-unsigned.apk` is an exact copy of the existing root `dist/manji-gateway-release-unsigned.apk`. It is **unsigned, cannot be installed directly, and is not a production release**. `/download` labels it separately. `GET /api/v1/app/unsigned/download` reads this exact file and streams an attachment with Android package MIME, its original filename, size and SHA-256. The file is not in `public`; there is no extra public copy, redirect to external storage or automatic signing.

The signed release catalog and `/v1/app/latest/download` keep their existing validation requirements. This unsigned artifact is excluded from Android's updater and successful-production-release claims. Replacing the source artifact later requires an explicit copy and renewed integrity verification; this restructuring did not run Gradle or alter the APK.

## Deployment

For production registration `503 DATABASE_UNAVAILABLE`, see the [confirmed PGRST106 investigation and targeted repair](docs/REGISTRATION.md). Use `npm run check:database -- --production` to test the real configured Supabase RPC without creating an account. Provider onboarding is not an authentication prerequisite.

Production environment setup for `https://api.manjifood.biz.id`: see the [source audit, required variables, Supabase setup and startup checks](docs/production-environment.md). Use [.env.production.example](.env.production.example) in the host secret manager; [.env.example](.env.example) retains sandbox development defaults. From `web`, run `npm run check:env -- --production` before deployment. The same validation runs at Node server startup. Existing `.env.local` stays untouched; do not include it in a deployment.

Supported values are exactly `PAYMENT_ENV=sandbox|production`, `PROVIDER_MODE=mock|official`, `STORE_DRIVER=pglite|supabase`. Production requires `production`/`official`/`supabase` and HTTPS. The official provider adapter remains disabled, so valid environment configuration cannot enable verified payments. See [this audit's validation record](IMPLEMENTATION_LOG.md).

For Docker, run `docker build -t manji-gateway .` from this repository root. The local `.dockerignore` excludes environment files, credentials and generated output. The existing Node server starts this Next.js application.

For the standalone GitHub repository, use its root (default/`.`) as Vercel Root Directory, Next.js, Node 24.x, Install Command `npm ci`, and Build Command `npm run build`. `vercel.json` records the commands and framework. Include `packages/` and `package-lock.json` in the source commit. See [the E404 fix, deployment settings and tracked-file cleanup](docs/VERCEL.md). Preserve the existing food site's routing.

`next.config.ts` traces files within this repository and explicitly includes the packaged SQL and APK artifacts for their routes, following [Next.js file tracing](https://nextjs.org/docs/app/api-reference/config/next-config-js/output). Verify the generated route `.nft.json` and the actual deployed download. The route returns a byte stream; an environment that buffers responses at Vercel's [4.5 MB payload limit](https://vercel.com/docs/functions/limitations) cannot deliver this 8,293,976-byte APK. Vercel documents [streaming responses](https://vercel.com/kb/guide/how-to-bypass-vercel-body-size-limit-serverless-functions) for larger responses, but hosted execution was not tested here. Tracing inclusion alone does not prove hosted download success. A normal Node/Docker host can serve the file at this location; no new external storage is introduced.

See [Vercel deployment](docs/VERCEL.md), [production configuration](docs/production-environment.md), [database setup](supabase/README.md) and [implementation log](IMPLEMENTATION_LOG.md). Official provider access remains disabled; sandbox cannot commit PAID.
