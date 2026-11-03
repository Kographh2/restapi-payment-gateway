# Package the existing canonical migrations; do not connect to a database.
$ErrorActionPreference = 'Stop'
$webRoot = Split-Path $PSScriptRoot -Parent
$outputPath = Join-Path $webRoot 'SUPABASE_SETUP.sql'
if (Test-Path -LiteralPath $outputPath) { throw 'SUPABASE_SETUP.sql already exists; refusing to overwrite it.' }
$names = @(
    '202611020001_manji_schema.sql',
    '202611020002_manji_commands.sql',
    '202611020003_manji_provider_worker.sql',
    '202611020004_manji_account_idempotency.sql',
    '202611020005_app_distribution.sql'
)
$header = @'
-- MANJI Gateway - paket SQL Supabase untuk instalasi awal.
-- Sumber resmi: ../supabase/migrations/20261102*.sql (5 migrasi, sesuai urutan).
-- Jalankan seluruh file di Supabase SQL Editor sebagai postgres/owner.
-- Gunakan hanya jika schema manji_gateway belum pernah dipasang.
-- Jika sudah terpasang sebagian, jalankan hanya migrasi lanjutan yang belum dipasang.
-- Setiap migrasi menggunakan transaksinya sendiri; blok sebelumnya tetap tersimpan
-- apabila blok berikutnya gagal. Jangan menjalankan ulang semua blok setelah gagal.
-- Paket ini tidak menghapus data dan tidak memuat migrasi historis 0001-0003,
-- auth fixture lokal, akun admin otomatis, password, atau credential aplikasi.
-- Bucket privat manji-app-releases harus belum ada sebelum migrasi 005.
-- Setelah selesai: tambahkan manji_gateway ke Exposed schemas di Supabase Data API.
-- Provisioning admin terpisah: ../scripts/provision-admin.sql (akun terverifikasi).
-- Belum dijalankan pada Supabase hosted oleh proses pembuatan file ini.
'@
$bundle = $header + "`n`n"
$sources = @()
foreach ($name in $names) {
    $sourcePath = Join-Path $webRoot ('..\supabase\migrations\' + $name)
    $body = [IO.File]::ReadAllText($sourcePath)
    $hash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $start = "-- BEGIN SOURCE: $name`n-- SOURCE SHA256: $hash`nbegin;`n`n"
    $end = "`ncommit;`n-- END SOURCE: $name`n`n"
    $bundle += $start + $body + $end
    $sources += @{body=$body;start=$start;end=$end}
}
[IO.File]::WriteAllText($outputPath,$bundle,(New-Object Text.UTF8Encoding($false)))
$written = [IO.File]::ReadAllText($outputPath)
$cursor = 0
foreach ($source in $sources) {
    $sectionStart = $written.IndexOf($source.start,$cursor,[StringComparison]::Ordinal)
    if ($sectionStart -lt $cursor) { throw 'Source ordering mismatch.' }
    $bodyStart = $sectionStart + $source.start.Length
    $sectionEnd = $written.IndexOf($source.end,$bodyStart,[StringComparison]::Ordinal)
    if ($sectionEnd -lt 0 -or $written.Substring($bodyStart,$sectionEnd-$bodyStart) -cne $source.body) { throw 'Source content changed.' }
    $cursor = $sectionEnd + $source.end.Length
}
if ([regex]::Matches($written,'(?m)^begin;$').Count -ne 5 -or [regex]::Matches($written,'(?m)^commit;$').Count -ne 5) { throw 'Transaction boundary mismatch.' }
Write-Output "Created: $outputPath"
Write-Output 'PASS: all five source contents unchanged and ordered; five separate transactions. Hosted execution: not performed.'
