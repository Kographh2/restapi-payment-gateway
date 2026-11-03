# Run in an interactive LOCAL PowerShell terminal. No Gradle or Android build.
[CmdletBinding()]
param(
    [string]$KeystorePath = (Join-Path $env:USERPROFILE '.manji-signing\manji-gateway-release.jks'),
    [string]$KeyAlias = 'manji-gateway-release',
    [string]$SdkRoot = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }),
    [string]$BuildToolsVersion = '35.0.0'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$webRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = [IO.Path]::GetFullPath((Join-Path $webRoot '..'))
$source = Join-Path $webRoot 'aplikasi\manji-gateway-release-unsigned.apk'
$output = Join-Path $webRoot 'aplikasi\manji-gateway-release.apk'
$reportPath = Join-Path $webRoot 'aplikasi\manji-gateway-release.verification.json'
$expectedSource = '1decb2582140ac3097fcecbedca408512a07269e4bfc1fc62db36f3fffd1fd46'
$tools = Join-Path $SdkRoot ('build-tools\' + $BuildToolsVersion)
$zipalign = Join-Path $tools 'zipalign.exe'
$signer = Join-Path $tools 'lib\apksigner.jar'
$aapt = Join-Path $tools 'aapt.exe'
$java = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\java.exe' } else { (Get-Command java.exe -ErrorAction Stop).Source }
$keytool = Join-Path (Split-Path $java -Parent) 'keytool.exe'
foreach ($required in @($source,$zipalign,$signer,$aapt,$java,$keytool)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing required file: $required" }
}
if ((Test-Path -LiteralPath $output) -or (Test-Path -LiteralPath $reportPath)) { throw 'Signed output or report already exists. Preserve/review it before signing again.' }
$sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sourceHash -ne $expectedSource) { throw 'Unsigned APK differs from the audited source. Nothing was signed.' }
$badging = (& $aapt dump badging $source | Out-String)
if ($LASTEXITCODE -ne 0 -or $badging -notmatch "package: name='id.biz.manjifood.gateway' versionCode='3' versionName='0.3.0'" -or $badging -match '(?m)^application-debuggable') { throw 'Source is not the expected non-debug MANJI Gateway release.' }
$KeystorePath = [IO.Path]::GetFullPath($KeystorePath)
if ($KeystorePath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Keystore must be stored outside the entire project.' }
if ($KeystorePath.StartsWith([IO.Path]::GetFullPath($env:TEMP) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Use durable storage for the release keystore, not a temporary directory.' }
$newKeystore = -not (Test-Path -LiteralPath $KeystorePath)
$keyDirectory = Split-Path $KeystorePath -Parent
if ($newKeystore) {
    if (-not (Test-Path -LiteralPath $keyDirectory)) {
        New-Item -ItemType Directory -Path $keyDirectory | Out-Null
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl.SetOwner($identity)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
        Set-Acl -LiteralPath $keyDirectory -AclObject $acl
    }
    Write-Host "Creating your durable RELEASE signing identity at $KeystorePath"
    Write-Host 'Keep an encrypted backup and retain the password for future app updates.'
} else { Write-Host "Using existing keystore: $KeystorePath (alias: $KeyAlias)" }

function Read-Password([string]$Prompt) {
    $secret = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secret.Dispose() }
}
$password = $null
$confirmation = $null
$oldStorePassword = [Environment]::GetEnvironmentVariable('MANJI_APK_STORE_PASSWORD','Process')
$oldKeyPassword = [Environment]::GetEnvironmentVariable('MANJI_APK_KEY_PASSWORD','Process')
$work = Join-Path $webRoot ('aplikasi\.signing-' + [Guid]::NewGuid().ToString('N'))
try {
    $password = Read-Password 'Keystore password (hidden; never enter it in chat)'
    if ($newKeystore) {
        if ($password.Length -lt 16) { throw 'Use a unique release password with at least 16 characters.' }
        $confirmation = Read-Password 'Confirm new keystore password'
        if ($password -cne $confirmation) { throw 'Passwords do not match. Nothing was signed.' }
    }
    [Environment]::SetEnvironmentVariable('MANJI_APK_STORE_PASSWORD',$password,'Process')
    [Environment]::SetEnvironmentVariable('MANJI_APK_KEY_PASSWORD',$password,'Process')
    $password = $null; $confirmation = $null
    if ($newKeystore) {
        & $keytool '-J-Xmx128m' -genkeypair -keystore $KeystorePath -storetype PKCS12 -alias $KeyAlias -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 -dname 'CN=MANJI Gateway Release, O=MANJI, C=ID' -storepass:env MANJI_APK_STORE_PASSWORD -keypass:env MANJI_APK_KEY_PASSWORD
        if ($LASTEXITCODE -ne 0) { throw 'Release keystore generation failed.' }
        $keyAcl = New-Object Security.AccessControl.FileSecurity
        $keyAcl.SetAccessRuleProtection($true,$false)
        $keyIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $keyAcl.SetOwner($keyIdentity)
        $keyAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($keyIdentity,'FullControl','Allow')))
        $keyAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),'FullControl','Allow')))
        Set-Acl -LiteralPath $KeystorePath -AclObject $keyAcl
    } else {
        $differentKeyPassword = Read-Password 'Key password (hidden; Enter to use keystore password)'
        if ($differentKeyPassword) { [Environment]::SetEnvironmentVariable('MANJI_APK_KEY_PASSWORD',$differentKeyPassword,'Process') }
        $differentKeyPassword = $null
    }
    $certificate = (& $keytool '-J-Xmx128m' '-J-Duser.language=en' -list -v -keystore $KeystorePath -alias $KeyAlias -storepass:env MANJI_APK_STORE_PASSWORD | Out-String)
    if ($LASTEXITCODE -ne 0 -or $certificate -match 'CN=Android Debug|Test Only|Not Production' -or $certificate -notmatch 'PrivateKeyEntry') { throw 'A valid non-test release private-key entry is required.' }
    $fingerprintMatch = [regex]::Match($certificate,'SHA256:\s*([A-Fa-f0-9:]{95})')
    if (-not $fingerprintMatch.Success) { throw 'Cannot read the release certificate fingerprint.' }
    $expectedSigner = $fingerprintMatch.Groups[1].Value.Replace(':','').ToLowerInvariant()
    New-Item -ItemType Directory -Path $work | Out-Null
    $aligned = Join-Path $work 'aligned.apk'
    $signed = Join-Path $work 'signed.apk'
    & $zipalign -P 16 4 $source $aligned
    if ($LASTEXITCODE -ne 0) { throw 'zipalign failed.' }
    & $java -Xmx128m -jar $signer sign --ks $KeystorePath --ks-key-alias $KeyAlias --ks-pass env:MANJI_APK_STORE_PASSWORD --key-pass env:MANJI_APK_KEY_PASSWORD --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false --debuggable-apk-permitted false --alignment-preserved true --out $signed $aligned
    if ($LASTEXITCODE -ne 0) { throw 'apksigner signing failed.' }
    $verification = (& $java -Xmx128m -jar $signer verify --verbose --print-certs $signed | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Signed APK signature verification failed.' }
    $signerMatch = [regex]::Match($verification,'Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]{64})')
    if (-not $signerMatch.Success -or $signerMatch.Groups[1].Value.ToLowerInvariant() -ne $expectedSigner -or $verification -notmatch 'Verified using v2 scheme[^\n]*: true' -or $verification -notmatch 'Verified using v3 scheme[^\n]*: true') { throw 'Verified signing identity or signature scheme mismatch.' }
    & $zipalign -c -P 16 4 $signed
    if ($LASTEXITCODE -ne 0) { throw 'Signed APK alignment verification failed.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $originalZip = [IO.Compression.ZipFile]::OpenRead($source)
    $signedZip = [IO.Compression.ZipFile]::OpenRead($signed)
    try {
        foreach ($entry in $originalZip.Entries) {
            $resultEntry = $signedZip.GetEntry($entry.FullName)
            if (-not $resultEntry -or $resultEntry.Length -ne $entry.Length) { throw "APK payload changed: $($entry.FullName)" }
            $originalStream = $entry.Open(); $signedStream = $resultEntry.Open()
            $hasher = [Security.Cryptography.SHA256]::Create()
            try {
                $before = [BitConverter]::ToString($hasher.ComputeHash($originalStream))
                $after = [BitConverter]::ToString($hasher.ComputeHash($signedStream))
                if ($before -cne $after) { throw "APK payload changed: $($entry.FullName)" }
            } finally { $originalStream.Dispose(); $signedStream.Dispose(); $hasher.Dispose() }
        }
    } finally { $originalZip.Dispose(); $signedZip.Dispose() }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sourceHash) { throw 'Original unsigned APK changed.' }
    $signedHash = (Get-FileHash -LiteralPath $signed -Algorithm SHA256).Hash.ToLowerInvariant()
    $report = [ordered]@{
        schema_version=1; filename='manji-gateway-release.apk'; application_id='id.biz.manjifood.gateway'; version_code=3; version_name='0.3.0'; min_sdk=26; target_sdk=35
        sha256=$signedHash; size_bytes=(Get-Item -LiteralPath $signed).Length; signer_sha256=$expectedSigner; source_sha256=$sourceHash
        verified_at=[DateTime]::UtcNow.ToString('o'); signature_verified=$true; v2=$true; v3=$true; alignment_verified=$true; payload_unchanged=$true; unsigned_preserved=$true; rebuilt=$false
        sdk_build_tools=$BuildToolsVersion; verification_output=$verification.Trim()
    }
    $temporaryReport = Join-Path $work 'verification.json'
    [IO.File]::WriteAllText($temporaryReport,($report | ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $signed -Destination $output
    Move-Item -LiteralPath $temporaryReport -Destination $reportPath
    Write-Host $verification
    Write-Host "Signed APK: $output"
    Write-Host "APK SHA-256: $signedHash"
    Write-Host "Certificate SHA-256: $expectedSigner"
    Write-Host 'PASS: signature, v2/v3, 16 KB alignment, unchanged APK payload, original unsigned APK preserved. No rebuild.'
} finally {
    [Environment]::SetEnvironmentVariable('MANJI_APK_STORE_PASSWORD',$oldStorePassword,'Process')
    [Environment]::SetEnvironmentVariable('MANJI_APK_KEY_PASSWORD',$oldKeyPassword,'Process')
    $password = $null; $confirmation = $null
    $resolvedWork = [IO.Path]::GetFullPath($work)
    $allowedWorkParent = [IO.Path]::GetFullPath((Join-Path $webRoot 'aplikasi')) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedWork.StartsWith($allowedWorkParent,[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to clean a path outside aplikasi.' }
    if (Test-Path -LiteralPath $resolvedWork) { Remove-Item -LiteralPath $resolvedWork -Recurse -Force }
}
