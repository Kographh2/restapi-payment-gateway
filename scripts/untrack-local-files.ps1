# Run locally before committing. Removes generated/sensitive files from the Git
# index only; preserves every local file and does not rewrite Git history.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    & git rm -r --cached --ignore-unmatch -- .next .next-local .next-distribution-build .next-distribution-test .sandbox .env .env.local .env.production .env.production.local key.txt tsconfig.tsbuildinfo
    if ($LASTEXITCODE -ne 0) { throw 'Git index cleanup failed. No local files were deleted.' }
    Write-Output 'Local files preserved. Review git status, then commit source changes and index removals together.'
} finally { Pop-Location }
