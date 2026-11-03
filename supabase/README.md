# Database MANJI Gateway

Semua SQL database yang disertakan bersama aplikasi web ada di folder ini. Schema aplikasi tetap `manji_gateway`; Supabase Auth dan Storage tetap menggunakan schema bawaan Supabase. Folder ini berisi definisi database, bukan salinan data pengguna dari server.

```text
supabase/
  SUPABASE_SETUP.sql               Paket lengkap untuk instalasi awal
  migrations/                     Lima migrasi aktif, sesuai urutan
  scripts/
    provision-admin.sql           Provisioning admin melalui psql
    verify.sql                    Pemeriksaan metadata setelah instalasi
  seed.sql                        Seed kosong; tanpa credential/data produksi
  seed/local-auth-fixture.sql      Khusus pengujian PostgreSQL/PGlite lokal
  archive/legacy-public/           Tiga migrasi lama, tidak untuk instalasi aktif
```

## Instalasi awal di Supabase

1. Gunakan project Supabase yang dipilih untuk environment aplikasi. Untuk project yang dipakai bersama aplikasi lain, tinjau schema, trigger Auth dan bucket yang sudah ada terlebih dahulu.
2. Jika `manji_gateway` belum dipasang, buka **SQL Editor**, gunakan koneksi owner/postgres, lalu jalankan seluruh isi [SUPABASE_SETUP.sql](SUPABASE_SETUP.sql). Ini memuat kelima migrasi aktif, masing-masing dengan transaksi sendiri. Jangan menjalankan paket gabungan dan kelima file individual sekaligus.
3. Tambahkan `manji_gateway` ke **Exposed schemas** pada pengaturan Data API Supabase. Grant dan RLS sudah ditentukan oleh migrasi; jangan menggantinya dengan grant umum.
4. Jalankan [scripts/verify.sql](scripts/verify.sql) untuk memeriksa tabel, RLS, fungsi, bucket privat dan konfigurasi publikasi Realtime. Script ini hanya membaca metadata database.
5. Konfigurasikan Supabase Auth, email/SMTP, redirect URL dan environment server mengikuti [panduan deployment](../docs/production-environment.md). Simpan URL/key project di konfigurasi environment yang sudah digunakan aplikasi, bukan di SQL.

Jika ada migrasi yang gagal, blok sebelumnya mungkin sudah tersimpan. Periksa hasilnya, perbaiki penyebabnya, lalu jalankan hanya migrasi yang belum berhasil. Paket gabungan bukan script yang dapat dijalankan berulang kali pada schema yang sudah ada.

## Database yang sudah terpasang

Jalankan hanya file yang belum diterapkan, berdasarkan riwayat deployment, dalam urutan berikut:

1. `migrations/202611020001_manji_schema.sql` — akun/profil, merchant, sesi/perangkat, tagihan, QR, sinyal, event/verifikasi pembayaran, webhook, audit, konfigurasi, idempotensi, pembatasan request, trigger, indeks, RLS dan Realtime.
2. `migrations/202611020002_manji_commands.sql` — command/RPC akun, merchant dan credential, audit dan webhook.
3. `migrations/202611020003_manji_provider_worker.sql` — penerimaan event provider terverifikasi dan worker webhook/retensi.
4. `migrations/202611020004_manji_account_idempotency.sql` — idempotensi mutasi akun.
5. `migrations/202611020005_app_distribution.sql` — katalog APK, audit/revokasi dan bucket privat `manji-app-releases`.

Migrasi 005 menolak bucket `manji-app-releases` yang sudah ada agar tidak mengubah bucket aplikasi lain secara diam-diam. Tinjau konflik tersebut sebelum melanjutkan. Tidak ada perubahan pada aturan otoritas pembayaran dalam penataan SQL ini.

## Administrator

Buat dan verifikasi akun melalui Supabase Auth terlebih dahulu. [scripts/provision-admin.sql](scripts/provision-admin.sql) adalah script operator dengan variabel **psql**, bukan SQL Editor langsung. Jalankan dari folder `web` melalui koneksi owner yang disimpan secara aman:

```powershell
psql -v ON_ERROR_STOP=1 -v admin_user_id='<UUID_AKUN_TERVERIFIKASI>' -f supabase/scripts/provision-admin.sql
```

Gunakan konfigurasi koneksi psql lokal/secret manager yang sudah disiapkan; jangan menaruh password database di source atau percakapan. Script menolak akun yang belum terverifikasi dan mencatat provisioning pada audit log. Tidak ada akun admin atau password default di paket instalasi.

## Pengembangan lokal dan arsip

`seed/local-auth-fixture.sql` hanya untuk database PostgreSQL/PGlite yang terisolasi. File tersebut meniru bagian Auth yang disediakan Supabase di server dan tidak boleh dijalankan pada Supabase hosted. Runtime sandbox lokal kini membaca fixture dan migrasi dari folder `web/supabase` ini. `GATEWAY_REPO_ROOT`, jika sengaja diatur, tetap dapat memilih root lain yang memiliki struktur `supabase/`.

`archive/legacy-public` mempertahankan migrasi historis `0001`–`0003` secara terpisah dari `migrations/`. Jangan memasukkannya ke instalasi schema MANJI Gateway yang aktif. Aplikasi dan paket instalasi gabungan tidak memuat arsip tersebut. Source lama di monorepo induk tetap utuh untuk kompatibilitas; seluruh file SQL yang diperlukan aplikasi web tersedia di folder ini.

Untuk memeriksa sinkronisasi paket gabungan dengan kelima migrasi aktif:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/export-supabase-sql.ps1 -Check
```

Pemeriksaan ini tidak terhubung ke Supabase. Paket SQL dan penataan folder tidak berarti database hosted sudah dipasang atau provider pembayaran sudah aktif.
