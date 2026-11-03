# Fixture lokal saja

`local-auth-fixture.sql` digunakan oleh PostgreSQL/PGlite sandbox lokal dan pengujian. File ini membuat pengganti lokal untuk sebagian fasilitas Supabase Auth beserta tabel sandbox.

Jangan jalankan file ini pada Supabase hosted. Auth di server sudah dikelola Supabase. File ini tidak dimasukkan ke `../SUPABASE_SETUP.sql`; `../seed.sql` sengaja tidak berisi data produksi atau credential.
