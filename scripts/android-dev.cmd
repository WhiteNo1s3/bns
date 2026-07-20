@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM =============================================================================
REM BNS — Windows: build Android APK, adb install, launch, live logcat
REM
REM Usage (from project root OR double-click / run from anywhere):
REM   scripts\android-dev.cmd              debug build + install + launch + logs
REM   scripts\android-dev.cmd build        debug APK only
REM   scripts\android-dev.cmd install      install last debug APK
REM   scripts\android-dev.cmd run          install + launch + logs (no rebuild)
REM   scripts\android-dev.cmd release      release APK + install + launch
REM   scripts\android-dev.cmd logs         live Flutter logcat only
REM   scripts\android-dev.cmd devices      list adb devices
REM
REM Needs: Flutter on PATH, Android SDK (adb), phone with USB debugging ON.
REM =============================================================================

set "ROOT=%~dp0.."
pushd "%ROOT%" || exit /b 1

set "PKG=com.whiteno1se.bns"
set "ACTIVITY=com.whiteno1se.bns/.MainActivity"
set "APK_DEBUG=build\app\outputs\flutter-apk\app-debug.apk"
set "APK_RELEASE=build\app\outputs\flutter-apk\app-release.apk"
set "DIST_DEBUG=dist\BNS-android-debug.apk"
set "DIST_RELEASE=dist\BNS-android.apk"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=all"

call :find_adb
if errorlevel 1 (
  echo [BNS] adb not found. Install Android SDK platform-tools.
  echo       Expected: %%LOCALAPPDATA%%\Android\Sdk\platform-tools\adb.exe
  popd
  exit /b 1
)

if /i "%MODE%"=="devices"  goto :devices
if /i "%MODE%"=="logs"     goto :logs
if /i "%MODE%"=="build"    goto :build_debug
if /i "%MODE%"=="install"  goto :install_debug
if /i "%MODE%"=="run"      goto :run_debug
if /i "%MODE%"=="release"  goto :all_release
if /i "%MODE%"=="all"      goto :all_debug
if /i "%MODE%"=="help"     goto :help
if /i "%MODE%"=="/?"       goto :help
if /i "%MODE%"=="-h"       goto :help

echo [BNS] Unknown command: %MODE%
goto :help

:help
echo.
echo BNS Android dev ^(Windows cmd^)
echo   scripts\android-dev.cmd              build debug + install + launch + logs
echo   scripts\android-dev.cmd build        debug APK only
echo   scripts\android-dev.cmd install      install last debug APK
echo   scripts\android-dev.cmd run          install + launch + logs
echo   scripts\android-dev.cmd release      release build + install + launch
echo   scripts\android-dev.cmd logs         live logcat ^(flutter + errors^)
echo   scripts\android-dev.cmd devices      list phones / emulators
echo.
popd
exit /b 0

:devices
echo [BNS] adb: %ADB%
"%ADB%" devices -l
popd
exit /b 0

:find_adb
set "ADB="
where adb >nul 2>&1
if not errorlevel 1 (
  for /f "delims=" %%A in ('where adb') do (
    set "ADB=%%A"
    goto :adb_ok
  )
)
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
  set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
  goto :adb_ok
)
if defined ANDROID_HOME if exist "%ANDROID_HOME%\platform-tools\adb.exe" (
  set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
  goto :adb_ok
)
if defined ANDROID_SDK_ROOT if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" (
  set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
  goto :adb_ok
)
exit /b 1
:adb_ok
exit /b 0

:need_device
"%ADB%" start-server >nul 2>&1
"%ADB%" get-state 1>nul 2>&1
if errorlevel 1 (
  echo [BNS] No device. Plug phone, enable USB debugging, allow this PC.
  echo [BNS] Then: scripts\android-dev.cmd devices
  "%ADB%" devices -l
  exit /b 1
)
exit /b 0

:need_flutter
where flutter >nul 2>&1
if errorlevel 1 (
  echo [BNS] flutter not on PATH. Open a Flutter-enabled terminal.
  exit /b 1
)
exit /b 0

:build_debug
call :need_flutter || (popd & exit /b 1)
echo [BNS] flutter pub get...
call flutter pub get
if errorlevel 1 (popd & exit /b 1)
echo [BNS] Building DEBUG APK...
call flutter build apk --debug
if errorlevel 1 (
  echo [BNS] Build failed.
  popd
  exit /b 1
)
if not exist "%APK_DEBUG%" (
  echo [BNS] APK missing: %APK_DEBUG%
  popd
  exit /b 1
)
if not exist dist mkdir dist
copy /Y "%APK_DEBUG%" "%DIST_DEBUG%" >nul
echo [BNS] APK: %CD%\%APK_DEBUG%
echo [BNS] Copy: %CD%\%DIST_DEBUG%
if /i "%MODE%"=="build" (popd & exit /b 0)
exit /b 0

:build_release
call :need_flutter || (popd & exit /b 1)
echo [BNS] flutter pub get...
call flutter pub get
if errorlevel 1 (popd & exit /b 1)
echo [BNS] Building RELEASE APK ^(obfuscated^)...
call flutter build apk --release --obfuscate --split-debug-info=build\symbols
if errorlevel 1 (
  echo [BNS] Build failed.
  popd
  exit /b 1
)
if not exist dist mkdir dist
copy /Y "%APK_RELEASE%" "%DIST_RELEASE%" >nul
echo [BNS] APK: %CD%\%APK_RELEASE%
echo [BNS] Copy: %CD%\%DIST_RELEASE%
exit /b 0

:install_apk
set "WHICH=%~1"
if not exist "!WHICH!" (
  echo [BNS] APK not found: !WHICH!
  echo [BNS] Run: scripts\android-dev.cmd build
  exit /b 1
)
call :need_device
if errorlevel 1 exit /b 1
echo [BNS] Installing: !WHICH!
"%ADB%" install -r "!WHICH!"
if errorlevel 1 (
  echo [BNS] Install failed. Try unplug/replug, revoke USB debug, retry.
  exit /b 1
)
echo [BNS] Installed OK.
exit /b 0

:launch
echo [BNS] Launching %PKG%...
"%ADB%" shell am start -n %ACTIVITY%
if errorlevel 1 (
  REM Fallback: monkey launch by package
  "%ADB%" shell monkey -p %PKG% -c android.intent.category.LAUNCHER 1
)
exit /b 0

:logs
call :need_device
if errorlevel 1 (popd & exit /b 1)
echo [BNS] Clearing logcat, then live: flutter + Android errors.
echo [BNS] Ctrl+C to stop.
"%ADB%" logcat -c
"%ADB%" logcat flutter:V *:E
popd
exit /b 0

:install_debug
call :install_apk "%APK_DEBUG%"
if errorlevel 1 (popd & exit /b 1)
popd
exit /b 0

:run_debug
call :install_apk "%APK_DEBUG%"
if errorlevel 1 (popd & exit /b 1)
call :launch
goto :logs

:all_debug
call :build_debug
if errorlevel 1 (popd & exit /b 1)
call :install_apk "%APK_DEBUG%"
if errorlevel 1 (popd & exit /b 1)
call :launch
goto :logs

:all_release
call :build_release
if errorlevel 1 (popd & exit /b 1)
call :install_apk "%APK_RELEASE%"
if errorlevel 1 (popd & exit /b 1)
call :launch
echo [BNS] Release installed. For live Flutter logs: scripts\android-dev.cmd logs
popd
exit /b 0
