# MANJI Gateway web application

SQL instalasi awal Supabase tersedia di root folder ini: [SUPABASE_SETUP.sql](SUPABASE_SETUP.sql). File tersebut menggabungkan lima migrasi aktif `20261102*.sql` dari `../supabase/migrations` sesuai urutan, tanpa mengubah isinya. Jalankan di Supabase SQL Editor sebagai owner/postgres hanya jika schema `manji_gateway` belum dipasang; jika sudah terpasang sebagian, gunakan hanya migrasi berikutnya yang belum dijalankan. Tiap migrasi memiliki transaksi sendiri. Setelah selesai, tambahkan `manji_gateway` ke Exposed schemas pada pengaturan Data API. Migrasi lama `0001`–`0003` dan fixture auth lokal tidak disertakan. File ini belum dijalankan pada Supabase hosted.

Run from monorepo root: npm ci, npm run sandbox:setup, npm run dev. Restricted Windows: set NEXT_WORKER_THREADS=true and npm run dev:local. Configure explicitly; no environment fallback. Build with npm run build and npm start on a host supporting worker processes.

This directory contains the existing Next.js application and the former dashboard UI package. Pages are under `src/app`, UI/styles under `src/components`, browser API/realtime helpers under `src/lib`, and backend modules under `src/services`. Shared contracts/types and Supabase migrations stay at repository root. There is one web package and one implementation of each feature.

From repository root, web-only validation is `npm run typecheck -w web`, `npm run lint -w web`, `npm run build -w web`. Root commands also target this workspace. `.env.example` and the unchanged local `.env.local` are now here. Existing database files in the application's `.sandbox` directory moved with it; no database was reset. Do not run sandbox setup over existing configuration.

Route groups organize login/registration and administrator/merchant pages without changing `/login`, `/register`, `/account`, `/auth/confirm` or `/admin`. `/merchant` hosts the existing merchant page and `/dashboard` preserves its former URL. Canonical `/v1/*`, compatible `/api/v1/*`, `/health`, new `/api/health`, `/docs` and `/openapi.json` remain on `https://api.manjifood.biz.id`.

## Sign the existing APK without rebuilding

See [local interactive signing and verification](docs/APK_SIGNING.md). The prepared script uses Android SDK zipalign/apksigner and stores a new password-protected release key outside the repository. The signed file target is `aplikasi/manji-gateway-release.apk`; the website uses `/aplikasi/manji-gateway-release.apk`, and `/api/v1/app/download` redirects there. Both the signed APK and its verification report must be present and match before this download is enabled. The existing unsigned file and release catalog remain available independently. Actual signing currently awaits local password entry because the Codex runtime rejected an unsandboxed launch; no signed APK is claimed yet.

## Existing unsigned APK

`aplikasi/manji-gateway-release-unsigned.apk` is an exact copy of the existing root `dist/manji-gateway-release-unsigned.apk`. It is **unsigned, cannot be installed directly, and is not a production release**. `/download` labels it separately. `GET /api/v1/app/unsigned/download` reads this exact file and streams an attachment with Android package MIME, its original filename, size and SHA-256. The file is not in `public`; there is no extra public copy, redirect to external storage or automatic signing.

The signed release catalog and `/v1/app/latest/download` keep their existing validation requirements. This unsigned artifact is excluded from Android's updater and successful-production-release claims. Replacing the source artifact later requires an explicit copy and renewed integrity verification; this restructuring did not run Gradle or alter the APK.

## Deployment

Production environment setup for `https://api.manjifood.biz.id`: see the [source audit, required variables, Supabase setup and startup checks](docs/production-environment.md). Use [.env.production.example](.env.production.example) in the host secret manager; [.env.example](.env.example) retains sandbox development defaults. From `web`, run `npm run check:env -- --production` before deployment. The same validation runs at Node server startup. Existing `.env.local` stays untouched; do not include it in a deployment.

Supported values are exactly `PAYMENT_ENV=sandbox|production`, `PROVIDER_MODE=mock|official`, `STORE_DRIVER=pglite|supabase`. Production requires `production`/`official`/`supabase` and HTTPS. The official provider adapter remains disabled, so valid environment configuration cannot enable verified payments. See [this audit's validation record](IMPLEMENTATION_LOG.md).

For Docker, run `docker build -f web/Dockerfile .` from repository root; keep root `.dockerignore` and shared packages available. The existing Node server starts the `web` application.

For Vercel, select `web` as Root Directory and permit source files outside that directory for the existing npm workspaces. Install from the monorepo root (`cd .. && npm ci` when the install command starts in `web`); build with `npm run build` in `web`. Configure existing server environment variables in the host secret manager. Preserve the existing food site's routing.

`next.config.ts` sets the monorepo tracing root and explicitly includes `./aplikasi/manji-gateway-release-unsigned.apk` for `/download` and the artifact route, following [Next.js file tracing](https://nextjs.org/docs/app/api-reference/config/next-config-js/output). Verify the generated route `.nft.json` and the actual deployed download. The route returns a byte stream; an environment that buffers responses at Vercel's [4.5 MB payload limit](https://vercel.com/docs/functions/limitations) cannot deliver this 8,293,976-byte APK. Vercel documents [streaming responses](https://vercel.com/kb/guide/how-to-bypass-vercel-body-size-limit-serverless-functions) for larger responses, but hosted execution was not tested here. Tracing inclusion alone does not prove hosted download success. A normal Node/Docker host can serve the file at this location; no new external storage is introduced.

See [restructure verification](../docs/deployment/web-restructure.md), [current deployment](../docs/deployment/MANJI.md) and [implementation log](../IMPLEMENTATION_LOG.md). Official provider access remains disabled; sandbox cannot commit PAID.
