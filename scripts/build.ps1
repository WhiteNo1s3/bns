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
    Write-Host "Building Android APK (perfect with .bns + icon)..." -ForegroundColor Green
    # Icon must be perfect: run flutter pub run flutter_launcher_icons:main first with relaxing color icon
    flutter build apk --release
    Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"
    Write-Host "Install and add BNS widget to home. .bns files will open and import."
}

if ($Target -eq "all" -or $Target -eq "ios") {
    Write-Host "Building iOS (HIGH-PROFILE iPhone target - nuke launch for WhiteNo1se Inc (SHALTIEL))..." -ForegroundColor Green
    # Icon perfect green smiling brain
    flutter build ios --release
    Write-Host "iOS IPA ready. .bns association for full data import. High-profile polish."
}

if ($Target -eq "all" -or $Target -eq "web") {
    flutter build web
}

if ($Target -eq "all" -or $Target -eq "macos") {
    Write-Host "Building clean native macOS (not iPhone apps on Mac)..." -ForegroundColor Green
    flutter build macos --release
    Write-Host "macOS app ready in build/macos/Build/Products/Release/"
    Write-Host "With Apple Silicon (M1/M2+), relevant to all kinds of people - everyone can afford it. Clean version for all. In US charts are nuts - high potential."
}

Write-Host "`nFor full .bns file association on Windows, register the extension manually or use a setup installer (InnoSetup / MSIX)."
Write-Host "macOS: .bns association via Info.plist (integrated - open .bns delivers full data via app)."
Write-Host "See docs for platform-specific association steps." -ForegroundColor Yellow
