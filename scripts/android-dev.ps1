# BNS — Windows Android: build, adb push/install, launch, logcat
# Prefer the .cmd wrapper for double-click:  scripts\android-dev.cmd
#
#   .\scripts\android-dev.ps1              # debug build + install + launch + logs
#   .\scripts\android-dev.ps1 build
#   .\scripts\android-dev.ps1 install
#   .\scripts\android-dev.ps1 run
#   .\scripts\android-dev.ps1 release
#   .\scripts\android-dev.ps1 logs
#   .\scripts\android-dev.ps1 devices

param(
    [Parameter(Position = 0)]
    [ValidateSet('all', 'build', 'install', 'run', 'release', 'logs', 'devices', 'help')]
    [string]$Command = 'all'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }
Set-Location $Root

$Pkg = 'com.whiteno1se.bns'
$Activity = 'com.whiteno1se.bns/.MainActivity'
$ApkDebug = 'build\app\outputs\flutter-apk\app-debug.apk'
$ApkRelease = 'build\app\outputs\flutter-apk\app-release.apk'

function Find-Adb {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'),
        (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'),
        (Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe')
    ) | Where-Object { $_ -and (Test-Path $_) }
    if ($candidates) { return $candidates[0] }
    throw "adb not found. Install Android SDK platform-tools (Android Studio)."
}

function Assert-Device($Adb) {
    & $Adb start-server | Out-Null
    $state = & $Adb get-state 2>$null
    if ($LASTEXITCODE -ne 0 -or $state -notmatch 'device') {
        Write-Host '[BNS] No device. USB debugging ON, allow this PC.' -ForegroundColor Yellow
        & $Adb devices -l
        throw 'No adb device'
    }
}

function Build-Debug {
    Write-Host '[BNS] flutter pub get...' -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'pub get failed' }
    Write-Host '[BNS] Building DEBUG APK...' -ForegroundColor Green
    flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { throw 'debug build failed' }
    New-Item -ItemType Directory -Force dist | Out-Null
    Copy-Item $ApkDebug 'dist\BNS-android-debug.apk' -Force
    Write-Host "[BNS] APK: $((Resolve-Path $ApkDebug).Path)"
}

function Build-Release {
    Write-Host '[BNS] flutter pub get...' -ForegroundColor Cyan
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'pub get failed' }
    Write-Host '[BNS] Building RELEASE APK (obfuscated)...' -ForegroundColor Green
    flutter build apk --release --obfuscate --split-debug-info=build\symbols
    if ($LASTEXITCODE -ne 0) { throw 'release build failed' }
    New-Item -ItemType Directory -Force dist | Out-Null
    Copy-Item $ApkRelease 'dist\BNS-android.apk' -Force
    Write-Host "[BNS] APK: $((Resolve-Path $ApkRelease).Path)"
}

function Install-Apk($Adb, $Path) {
    if (-not (Test-Path $Path)) { throw "APK missing: $Path — run build first" }
    Assert-Device $Adb
    Write-Host "[BNS] Installing $Path" -ForegroundColor Cyan
    & $Adb install -r $Path
    if ($LASTEXITCODE -ne 0) { throw 'adb install failed' }
    Write-Host '[BNS] Installed OK.' -ForegroundColor Green
}

function Launch-App($Adb) {
    Write-Host "[BNS] Launching $Pkg..." -ForegroundColor Cyan
    & $Adb shell am start -n $Activity
    if ($LASTEXITCODE -ne 0) {
        & $Adb shell monkey -p $Pkg -c android.intent.category.LAUNCHER 1
    }
}

function Show-Logs($Adb) {
    Assert-Device $Adb
    Write-Host '[BNS] Live logcat (flutter + errors). Ctrl+C to stop.' -ForegroundColor Yellow
    & $Adb logcat -c
    & $Adb logcat flutter:V *:E
}

$Adb = Find-Adb
Write-Host "[BNS] adb: $Adb" -ForegroundColor DarkGray

switch ($Command) {
    'help' {
        Write-Host @'
BNS Android dev (Windows)
  .\scripts\android-dev.ps1              debug build + install + launch + logs
  .\scripts\android-dev.ps1 build
  .\scripts\android-dev.ps1 install
  .\scripts\android-dev.ps1 run          install + launch + logs
  .\scripts\android-dev.ps1 release
  .\scripts\android-dev.ps1 logs
  .\scripts\android-dev.ps1 devices
Or: scripts\android-dev.cmd  (same commands)
'@
    }
    'devices' { & $Adb devices -l }
    'build'   { Build-Debug }
    'install' { Install-Apk $Adb $ApkDebug }
    'run' {
        Install-Apk $Adb $ApkDebug
        Launch-App $Adb
        Show-Logs $Adb
    }
    'release' {
        Build-Release
        Install-Apk $Adb $ApkRelease
        Launch-App $Adb
        Write-Host '[BNS] For logs: .\scripts\android-dev.ps1 logs' -ForegroundColor Cyan
    }
    'logs' { Show-Logs $Adb }
    'all' {
        Build-Debug
        Install-Apk $Adb $ApkDebug
        Launch-App $Adb
        Show-Logs $Adb
    }
}
