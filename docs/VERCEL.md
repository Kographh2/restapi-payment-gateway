# Deploy repository web ke Vercel

Commit `55eb371` berisi aplikasi web di root GitHub, tanpa root monorepo atau folder `packages` yang sebelumnya berada di luar aplikasi. Dependensi `@manji/contracts: "*"` membuat npm mencari paket privat tersebut di registry publik dan menghasilkan E404. Aplikasi sekarang menyertakan empat paket lokal di `packages/`, dependensi `file:`, lockfile sendiri, devDependencies, loader TypeScript dan konfigurasi ESLint. Tidak ada paket privat yang perlu diterbitkan ke npm atau diakses dengan token npm.

## Pengaturan project

Untuk repository `restapi-payment-gateway` yang root-nya langsung berisi `src/` dan `package.json`:

| Pengaturan | Nilai |
| --- | --- |
| Root Directory | Root repository, kosong/default atau `.`; jangan `web` |
| Framework Preset | Next.js |
| Node.js | 24.x, mengikuti `engines` di package.json |
| Install Command | `npm ci` |
| Build Command | `npm run build` |
| Output Directory | Default Next.js (`.next`) |

`vercel.json` menetapkan framework, install command dan build command. Root Directory tetap merupakan pengaturan project Vercel. Jika memasang dari monorepo lama, Root Directory adalah `web`; setelah perubahan ini seluruh dependency aplikasi sudah tersedia di dalam folder web itu sendiri.

Tambahkan environment produksi ke **Project Settings → Environment Variables** dengan checklist [.env.production.example](../.env.production.example) dan [panduan konfigurasi](production-environment.md). Jangan mengunggah `.env`, private key atau password signing. Validasi startup tetap menolak konfigurasi yang belum lengkap; perbaikan dependency tidak mengaktifkan provider pembayaran resmi. Database Supabase hosted tetap harus disiapkan menggunakan [supabase/](../supabase/README.md).

## Bersihkan berkas yang sudah terlanjur dilacak Git

Pemeriksaan commit saat ini menemukan `.next`, `.next-local`, `.next-distribution-build`, `.sandbox`, `.env`, `key.txt` dan `tsconfig.tsbuildinfo` telah dilacak Git. `.gitignore` baru tidak dapat menghapus file-file tersebut dari commit yang sudah ada. Jalankan di PowerShell lokal dari root repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/untrack-local-files.ps1
```

Script hanya melepas file tersebut dari index, tanpa menghapus salinan lokal atau mengubah riwayat Git. Tinjau `git status`, lalu commit penghapusan dari index bersama seluruh perbaikan source, folder `packages`, folder `supabase`, `package-lock.json` dan `vercel.json`. Jangan menambahkan kembali `.env` atau `key.txt`. Bila file yang sudah masuk Git berisi credential asli, ganti credential itu melalui pemilik layanannya; menghapusnya pada commit baru tidak menghapus salinan dalam riwayat lama.

Workspace Codex sesi ini menyediakan `.git` sebagai area baca saja, sehingga perubahan index harus dijalankan melalui terminal lokal. Tidak ada commit, push, perubahan secret Vercel atau deployment remote yang dijalankan otomatis oleh perbaikan ini.

`.vercelignore` juga mengecualikan cache/build lokal dan file sensitif untuk upload CLI. Gunakan source checkout bersih untuk build Git agar Vercel tidak menerima `.next` hasil mesin lokal. Dokumentasi: [Vercel project settings](https://vercel.com/docs/project-configuration/project-settings), [Node.js versions](https://vercel.com/docs/functions/runtimes/node-js/node-js-versions), [deployment exclusions](https://vercel.com/docs/deployments/vercel-ignore), [npm ci](https://docs.npmjs.com/cli/v11/commands/npm-ci/).

## Pemeriksaan lokal

```powershell
npm ci
npm run typecheck
npm run lint
npm run test:deployment
npm run test:env
npm run build
```

Gunakan konfigurasi environment yang sesuai secara lokal. Jangan mengubah production ke sandbox untuk meloloskan deployment. Hasil validasi aktual dan keterbatasan mesin dicatat di [IMPLEMENTATION_LOG.md](../IMPLEMENTATION_LOG.md); dokumentasi ini sendiri bukan bukti deployment atau koneksi Supabase berhasil.
