# BNS Build & Package script (PowerShell)
# Run from project root after flutter pub get

param(
    [string]$Target = "all"
)

Write-Host "=== BNS Packaging ===" -ForegroundColor Cyan

if ($Target -eq "all" -or $Target -eq "windows") {
    Write-Host "Building Windows..." -ForegroundColor Green
    flutter build windows --release
    Write-Host "Windows exe ready in build/windows/x64/runner/Release/"
}

if ($Target -eq "all" -or $Target -eq "android") {
    Write-Host "Building Android APK..." -ForegroundColor Green
    flutter build apk --release
    Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"
}

if ($Target -eq "all" -or $Target -eq "web") {
    flutter build web
}

Write-Host "`nFor full .bns file association on Windows, register the extension manually or use a setup installer (InnoSetup / MSIX)."
Write-Host "See docs for platform-specific association steps." -ForegroundColor Yellow
