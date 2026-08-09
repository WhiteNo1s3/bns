# Creates YOUR Android release signing certificate — run ONCE, keep forever.
#
# What it does:
#   1. Finds keytool (JDK / Android Studio's bundled JBR).
#   2. Generates android/bns-release.jks (your certificate, valid ~27 years).
#   3. Writes android/key.properties so gradle picks it up automatically.
# After this, every `flutter build apk --release` (or scripts/build.ps1) is
# signed with YOUR certificate — a "certified" build, and the same identity
# the Play Store will require if you publish there later.
#
# IMPORTANT:
#   - The .jks and key.properties are GITIGNORED. Never commit or share them.
#   - BACK UP android/bns-release.jks + the password somewhere safe (e.g. a
#     password manager + a copy on another disk). If they are lost, a future
#     update can NOT be installed over the old app — Android sees a stranger.
#   - Updates must always be signed with this same certificate.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$jksPath = Join-Path $root "android\bns-release.jks"
$propsPath = Join-Path $root "android\key.properties"

if (Test-Path $jksPath) {
    Write-Host "A release keystore already exists: $jksPath" -ForegroundColor Yellow
    Write-Host "You almost never want a second one (updates must keep the SAME certificate)."
    Write-Host "Delete it manually first if you truly want to start over."
    exit 1
}

# --- find keytool ---
$keytool = $null
if ($env:JAVA_HOME -and (Test-Path "$env:JAVA_HOME\bin\keytool.exe")) {
    $keytool = "$env:JAVA_HOME\bin\keytool.exe"
} else {
    $candidates = @(
        "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
        "$env:LOCALAPPDATA\Programs\Android Studio\jbr\bin\keytool.exe"
    ) + (Get-Command keytool -ErrorAction SilentlyContinue | ForEach-Object Source)
    $keytool = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $keytool) {
    Write-Host "keytool not found. Install a JDK or Android Studio, or set JAVA_HOME." -ForegroundColor Red
    exit 1
}
Write-Host "Using keytool: $keytool"

# --- ask for the password (this is YOURS — store it in a password manager) ---
$pw1 = Read-Host "Choose a keystore password (min 6 chars)" -AsSecureString
$pw2 = Read-Host "Type it again" -AsSecureString
$p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw1))
$p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw2))
if ($p1 -ne $p2) { Write-Host "Passwords don't match." -ForegroundColor Red; exit 1 }
if ($p1.Length -lt 6) { Write-Host "Too short (min 6)." -ForegroundColor Red; exit 1 }

& $keytool -genkeypair -v `
    -keystore $jksPath `
    -alias bns `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $p1 -keypass $p1 `
    -dname "CN=BNS, O=whiteno1se enterprise (SHALTIEL), C=IL"
if ($LASTEXITCODE -ne 0) { Write-Host "keytool failed." -ForegroundColor Red; exit 1 }

# key.properties: read by android/app/build.gradle.kts (storeFile is
# resolved relative to the android/ folder).
@"
storePassword=$p1
keyPassword=$p1
keyAlias=bns
storeFile=bns-release.jks
"@ | Set-Content -Path $propsPath -Encoding ASCII

Write-Host ""
Write-Host "Done. Release builds are now signed with YOUR certificate." -ForegroundColor Green
Write-Host "  Keystore:   $jksPath"
Write-Host "  Properties: $propsPath"
Write-Host ""
Write-Host "NOW BACK UP the .jks file + password (password manager + second disk)." -ForegroundColor Yellow
Write-Host "Next: .\scripts\build.ps1 -Target android  ->  a certified APK." -ForegroundColor Cyan
