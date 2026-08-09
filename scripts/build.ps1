# BNS Build & Package script (PowerShell)
# Run from project root. Requires: Flutter SDK on PATH.
#
# Targets this machine can build:
#   windows  — needs Visual Studio Build Tools (C++ workload)
#   android  — needs Android SDK + JDK 17 (set JAVA_HOME if gradle can't find it)
# Targets that need a Mac (config is ready, build there):
#   ios, macos
# Target that needs Linux:
#   linux
#
# Note: there is intentionally NO web target — BNS uses dart:io (local files,
# LAN sockets) by design. Privacy-first native app on every platform.

param(
    [string]$Target = "host",   # host = everything buildable on this machine
    [switch]$PackageWindows,    # also zip the Windows build for testers
    [switch]$DiagAndroid        # also build a no-R8 diagnostic APK
)

Write-Host "=== BNS Packaging ===" -ForegroundColor Cyan

# Version straight from pubspec — every artifact is named for its version,
# so GitHub releases stay unambiguous (special build per version).
$Version = ((Get-Content "pubspec.yaml" | Select-String '^version:') -replace 'version:\s*', '' -replace '\+.*', '').Trim()
Write-Host "Version: $Version"

if ($Target -eq "host" -or $Target -eq "windows") {
    Write-Host "Building Windows..." -ForegroundColor Green
    flutter build windows --release
    Write-Host "Windows exe: build\windows\x64\runner\Release\bns.exe"
    if ($PackageWindows) {
        # One zip a tester can unzip anywhere and double-click bns.exe —
        # fully self-contained, no installer, no admin rights.
        New-Item -ItemType Directory -Force dist | Out-Null
        Compress-Archive -Path "build\windows\x64\runner\Release\*" `
            -DestinationPath "dist\BNS-v$Version-windows-x64.zip" -Force
        Write-Host "Tester package: dist\BNS-v$Version-windows-x64.zip (unzip + run bns.exe; optional: scripts\register-bns.ps1 for .bns double-click)"
    }
}

if ($Target -eq "host" -or $Target -eq "android") {
    Write-Host "Building Android APK (obfuscated release)..." -ForegroundColor Green
    # Ship builds, not source: AOT + Dart symbol obfuscation (+ R8 on the JVM
    # side, see android/app/build.gradle.kts). Symbol maps land in
    # build\symbols — keep them if you ever need to read a crash stack.
    flutter build apk --release --obfuscate --split-debug-info=build\symbols
    Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
    New-Item -ItemType Directory -Force dist | Out-Null
    Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "dist\BNS-v$Version-android.apk" -Force
    if (Test-Path "android\key.properties") {
        Write-Host "Certified build (your own release certificate): dist\BNS-v$Version-android.apk" -ForegroundColor Green
    } else {
        Write-Host "NOTE: debug-signed (no release keystore yet). Run scripts\make-keystore.ps1 ONCE for certified builds." -ForegroundColor Yellow
        Write-Host "APK copied to: dist\BNS-v$Version-android.apk"
    }
    Write-Host "Install and add the BNS widgets to home. .bns files open and import."
    if ($DiagAndroid) {
        # Diagnostic twin without R8/obfuscation: if the hardened APK
        # misbehaves on a device and this one doesn't, R8 rules are the bug.
        Write-Host "Building DIAGNOSTIC APK (no R8, no obfuscation)..." -ForegroundColor Yellow
        $env:ORG_GRADLE_PROJECT_bnsNoMinify = "true"
        flutter build apk --release
        Remove-Item Env:ORG_GRADLE_PROJECT_bnsNoMinify
        New-Item -ItemType Directory -Force dist | Out-Null
        Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "dist\BNS-android-DIAG.apk" -Force
        Write-Host "Diagnostic APK: dist\BNS-android-DIAG.apk"
    }
}

if ($Target -eq "ios" -or $Target -eq "macos") {
    Write-Host "iOS/macOS compile only on a Mac (Xcode is macOS-only)." -ForegroundColor Yellow
    Write-Host "On the Mac: ./scripts/build-apple.sh   (guide: docs/apple-build-guide.md)"
}

if ($Target -eq "linux") {
    Write-Host "Building Linux (run on a Linux machine)..." -ForegroundColor Green
    flutter build linux --release
}
