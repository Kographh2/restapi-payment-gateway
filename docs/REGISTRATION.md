# Investigasi registrasi produksi

Pada 2026-11-03, probe pada `https://api.manjifood.biz.id/health` dan POST `/v1/auth/register` dengan body `{}` sama-sama menerima **503 DATABASE_UNAVAILABLE**. Tidak ada akun atau email dibuat. Request ID awal: health `28d84eac-3d62-4b97-8cb0-264ca38a58dc`; register `317b4c81-aa18-4b02-92d1-a1382ae0aa72`.

Probe terpisah menggunakan konfigurasi Supabase produksi lokal yang APP_BASE_URL-nya cocok dengan origin produksi menjalankan RPC read-only `manji_gateway.account_command(public.configuration)`. PostgREST menjawab **406/PGRST106**. Itu membuktikan project Supabase yang dikonfigurasi menolak pemilihan schema `manji_gateway`; bukan bukti password pengguna salah atau provider pembayaran dibutuhkan. Nilai credential, URL project, request signup, error details/hint dan data pengguna tidak ditampilkan.

## Jalur kegagalan

`POST /v1/auth/register` → validasi konfigurasi server → adapter Supabase service-role → RPC `account_command(rate)` → validasi input → RPC `account_command(public.configuration)` → Supabase Auth `signUp`.

Rate limit dijalankan sebelum validasi payload. Karena schema RPC ditolak, bahkan payload kosong berhenti pada 503 sebelum Supabase Auth dipanggil. Sebelumnya `SupabaseDatabase.rpc` meneruskan hanya `error.message` ke pemetaan generik, sehingga kode/status upstream hilang dan pengguna hanya melihat “Database belum tersedia”. Audit `request.log` juga menggunakan schema yang sama dan dapat ikut gagal.

Warning onboarding berasal dari instrumentation startup. Tidak ada pemanggilan provider pada jalur registrasi, login atau review merchant. `OfficialProviderAdapter` tetap menolak verifikasi dan QR dinamis; produksi tetap menolak mock. Startup sekarang melaporkan kapabilitas tersebut sebagai satu event info per proses, bukan warning berulang yang menyerupai penyebab kegagalan autentikasi.

## Perbaikan konfigurasi produksi

1. Pada project Supabase yang sama dengan konfigurasi Vercel, buka **Data API → Exposed schemas**.
2. **Tambahkan** `manji_gateway`, pertahankan semua schema yang sudah ada, lalu simpan.
3. Jika override `pgrst.db_schemas` di role `authenticator` menghalangi konfigurasi dashboard, tinjau hasil `supabase/scripts/verify.sql` lalu gunakan [skrip perbaikan owner](../supabase/scripts/expose-manji-schema.sql). Script mempertahankan allowlist eksplisit dan scope database yang ada, menambah hanya schema gateway dan memberi notifikasi reload konfigurasi/cache. Bila allowlist tidak tersedia, script menolak menebak dan mengarahkan ke dashboard.
4. Jika hasil berikutnya PGRST202/42883 atau 42P01/3F000, periksa kelima migrasi aktif dan cache PostgREST. Jika 42501, periksa grant USAGE/EXECUTE service_role dari migrasi. Jangan menjalankan GRANT ALL, mematikan RLS, memindahkan RPC ke public, atau melewati database/rate checks untuk menutupi masalah.
5. Jalankan diagnostik dan verifikasi ulang endpoint sebelum menyatakan masalah selesai.

Penjelasan resmi: [custom schema Supabase](https://supabase.com/docs/guides/api/using-custom-schemas), [PGRST106 dan override authenticator](https://supabase.com/kb/troubleshooting/pgrst106-the-schema-must-be-one-of-the-following-error-when-querying-an-exposed-schema), [kode error PostgREST](https://docs.postgrest.org/en/v16/references/errors.html).

## Diagnostik dan log aman

```powershell
npm run check:database -- --production
npm run check:database -- --production --endpoint
npm run test:registration
```

Command pertama hanya membaca konfigurasi pendaftaran melalui RPC, tidak membuat user atau mengubah data. Command kedua menambah GET health dan satu POST payload invalid; POST tetap melewati rate limiter dan audit asli. Kredensial dibaca dari environment secara lokal, tidak dipasang pada query string atau dicetak. Tidak ada retry signup otomatis yang berisiko membuat akun/email ganda.

Event kegagalan berisi `request_id`, operation yang sudah disanitasi, subsystem, nama RPC/command yang diizinkan, kategori kegagalan, kode upstream dan status. Field log ditentukan secara eksplisit; tidak ada serialisasi Error/stack, headers, URL, body, password, token, email atau row SQL. Event kegagalan audit tetap dibedakan melalui command `request.log` dan request ID yang sama. Konfigurasi gagal hanya mencetak nama field yang bermasalah, bukan nilainya.

Contoh diagnosis terkonfirmasi:

```json
{"event":"dependency_failure","subsystem":"database.supabase","failure":"schema_not_exposed","rpc":"account_command","command":"public.configuration","upstream_code":"PGRST106","upstream_status":406}
```

## Batas akses dan verifikasi

Sesi ini memiliki credential Data API tetapi tidak memiliki koneksi SQL owner atau akses pengaturan project Supabase/Vercel. Perubahan Exposed schemas tidak dapat diterapkan melalui service-role REST client itu sendiri. Script owner disediakan dan diuji pada PostgreSQL lokal; tidak ada pengubahan role/configuration remote yang dijalankan oleh kode diagnostik.

Kode lokal dan keberhasilan tes tidak membuktikan deployment sudah diperbarui. Probe invalid dapat membuktikan rate RPC sudah berfungsi, tetapi tidak membuktikan pengiriman email atau signup valid selesai. Signup produksi penuh memerlukan alamat email uji milik operator. Hasil akhir dan waktu pemeriksaan terbaru dicatat di IMPLEMENTATION_LOG.md; jangan menyatakan produksi sehat selama endpoint masih mengembalikan 503.
