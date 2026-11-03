# Sign the existing MANJI Gateway APK

Run this from `web` in an interactive local PowerShell terminal:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\sign-existing-apk.ps1
```

The script requests a hidden password locally. A new password must contain at least 16 characters and be confirmed. Passwords are never written to files, command arguments, source, reports or chat. They are passed to SDK tools through temporary process environment variables, restored in `finally`.

The default durable keystore is `%USERPROFILE%\.manji-signing\manji-gateway-release.jks`, outside the entire repository. New keys use PKCS12, RSA 4096, SHA256withRSA and a 10,000-day certificate. The new signing directory and key have Windows ACLs restricted to the current user and SYSTEM. Retain an encrypted backup of the key and its password for subsequent app updates. If an existing release key is elsewhere, use `-KeystorePath 'C:\secure-location\release.jks' -KeyAlias 'your-alias'`; it must be outside the project and temporary directory. Existing keystores are never replaced. Debug/test signing certificates are rejected.

Only the existing `aplikasi/manji-gateway-release-unsigned.apk` is used. The script pins its audited SHA-256, checks its manifest, calls Android SDK `zipalign -P 16 4`, signs a separate staged APK with Android SDK `apksigner`, then runs `apksigner verify --verbose --print-certs` and `zipalign -c -P 16 4`. It checks v2/v3 signatures and the keystore certificate fingerprint, hashes every original ZIP entry to confirm the application payload is unchanged, and verifies the unsigned APK is unchanged. It does not execute Gradle or rebuild Android.

Successful signing produces:

- `web/aplikasi/manji-gateway-release.apk`
- `web/aplikasi/manji-gateway-release.verification.json` with the signed file SHA-256, SHA-256 certificate fingerprint and actual verification output. The report contains public verification metadata only.

The script refuses to overwrite either existing result. Partial signing work is staged in a unique directory within `aplikasi`, cleaned after execution. Keep signing credentials out of commits; both root and web ignore rules exclude keystore/private-key formats. No Git repository was present in the supplied checkout, and no commit was made.

The website's stable-channel fallback button uses `/aplikasi/manji-gateway-release.apk`; `/api/v1/app/download` redirects to that same URL. The canonical route serves the APK only with a matching successful verification report and file checksum; missing files return 404 and inconsistent evidence or modified bytes return 503. GET and HEAD provide file size, APK SHA-256 and certificate SHA-256 headers. This serves private on-disk files through a Node route, not `public/`. Include the signed APK **and its report** when packaging/deploying the website; Next output tracing lists both. Signing locally does not deploy the site.

The original unsigned file and `/api/v1/app/unsigned/download` remain intact. The existing protected stable/beta release catalog, private Storage, history, revocation and native updater are unchanged. This explicit download of the existing signed archive does not insert a catalog record, fabricate build/install evidence, or claim physical-device acceptance. When a registered catalog release exists, the original catalog controls remain available.

Current execution limitation: the Codex runtime refused the requested unsandboxed launch (`sandbox_approval: false`). The local interactive command above is required to create the keystore outside the writable workspace and obtain a password. Until it succeeds, no signed APK or certificate fingerprint exists and the website refuses to offer this archive as a signed download.
