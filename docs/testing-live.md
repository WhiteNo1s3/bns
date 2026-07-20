# Live testing — phone + BlueStacks + laptop ("make testing alive completely")

The test bench: Galaxy S23 Ultra (real device), BlueStacks (second Android),
the Windows exe (third participant + LAN peer), Kubuntu laptop (fourth, Linux).
All artifacts come from `scripts\build.ps1`; testers get files from `dist\`.

## The artifacts (dist\)
| File | What it is |
|---|---|
| `BNS-android.apk` | The real thing: R8 + obfuscated release |
| `BNS-android-DIAG.apk` | Diagnostic twin: same code, NO R8/obfuscation |
| `BNS-windows-x64.zip` | Unzip anywhere → run `bns.exe` (no install, no admin) |
| `bns-web.html` | The Explorer (double-click, any browser) |

Build them all: `.\scripts\build.ps1 -Target host -PackageWindows -DiagAndroid`

## Galaxy S23 Ultra — hook it up once
1. Settings → About phone → Software information → tap **Build number** 7× (developer mode).
2. Settings → Developer options → enable **USB debugging**.
3. Plug USB into the PC → tap **Allow** on the phone.
4. Verify: `adb devices` shows the phone (adb lives at
   `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`).

### One command (Windows) — build, adb install, launch, live logs
From the repo root, phone plugged in with USB debugging:

```cmd
scripts\android-dev.cmd
```

Same thing in PowerShell: `.\scripts\android-dev.ps1`

| Command | What it does |
|---|---|
| `scripts\android-dev.cmd` | **Debug** build → `adb install -r` → open app → live `logcat` |
| `scripts\android-dev.cmd build` | Debug APK only (`dist\BNS-android-debug.apk`) |
| `scripts\android-dev.cmd install` | Install last debug APK |
| `scripts\android-dev.cmd run` | Install + launch + logs (no rebuild) |
| `scripts\android-dev.cmd release` | Obfuscated release + install + launch |
| `scripts\android-dev.cmd logs` | Live Flutter + error logcat only |
| `scripts\android-dev.cmd devices` | `adb devices -l` |

Needs: Flutter on PATH, Android SDK platform-tools, USB debugging allowed.

Manual adb (if you already have an APK):
```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r "dist\BNS-android-debug.apk"
& $adb logcat -c
& $adb logcat flutter:V *:E
```

## Black screen triage (the 2026-07-06 bug)
Root cause found in code: `main()` awaited the Android 13+ notification
PERMISSION DIALOG (plus store pruning) BEFORE the first frame — anything
blocking/failing there = black screen forever. Fixed: `runApp` now runs
first, all startup chores run after the UI exists, each wrapped so a failed
chore can never kill the launch ("the first frame is sacred").

If a black screen ever returns, bisect in two installs:
1. `BNS-android.apk` black, `BNS-android-DIAG.apk` fine → **R8 stripped
   something**: get the class name from `adb logcat -d *:E` and add a keep
   rule to `android/app/proguard-rules.pro`.
2. Both black → startup crash: `adb logcat -d *:E flutter:V` has the stack.

## BlueStacks as the second phone (LAN sync partner)
1. BlueStacks Settings → Advanced → enable **Android Debug Bridge (ADB)** —
   it shows a port, usually 5555.
2. `& $adb connect 127.0.0.1:5555` → `adb devices` now lists it.
3. `& $adb -s 127.0.0.1:5555 install -r "dist\BNS-android.apk"`.
4. BlueStacks + phone + the Windows exe are all LAN peers: open the Sync
   screen on two of them → pair with the typed code → watch auto-sync.
   (BlueStacks networking is NAT'd — if discovery doesn't see it, test
   phone ↔ Windows exe instead; that's the honest pair anyway.)

## Live develop-on-device (hot reload on the real phone)
```powershell
cd "C:\Dev\BNS claude fable"
flutter devices          # phone should be listed
flutter run -d <device-id>   # debug build, hot reload with 'r', logs live
```

## Two "users" on one PC (LAN + multi-user testing)
```powershell
.\dist\windows\bns.exe --data-dir C:\temp\user1
.\dist\windows\bns.exe --data-dir C:\temp\user2
```

## Kubuntu laptop — install Flutter once
```bash
sudo apt install git curl unzip xz-utils zip clang cmake ninja-build \
     pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
flutter doctor           # Linux desktop target is enough; Android needs
                         # Android Studio or cmdline-tools if wanted there
git clone https://github.com/benshaltiel/bns.git && cd bns
flutter pub get && flutter test && flutter build linux --release
```

## Every test session, quickly
1. `flutter test` (20 tests — containers, tamper, family share, keybinds).
2. Phone: install fresh APK → open → Today renders? add task → widget updates?
   🎤 widget button → app opens already recording?
3. Phone ↔ PC exe on one Wi-Fi: pair (share name shows!), sync, verify data.
4. Graceful close → `Documents\exports\BNS_Latest_*.bns` exists → open it in
   the Explorer (`dist\bns-web.html`) → seal verified banner.
5. Family file: mark an event "family can know" → Make the family file →
   open in Explorer → only that event visible.

## Android device test bundle (Pass 7, 2026-07-20)

Primary test surface is **Android**.

**On Windows (owner path):** one command does build + adb push + launch + logs:

```cmd
scripts\android-dev.cmd
```

- Debug APK also copied to `dist\BNS-android-debug.apk`
- Linux rebuild helper: `./scripts/build-android.sh`

### What to try on the phone
1. **Tap done** → quiet ✓. **Tap again** → "Open again. That's fine." (must never trap you)
2. **Long-press** → Not today (no reason). Tap row again → open again
3. **Something different** multi-day + companion; tap card to edit
4. **Doctor visit** mic + optional re-read words
5. Small phone: no button collisions, FAB not covering list, rotate if you want
6. Sync: Easier reading, soft list-ready note

If anything makes you want to throw the phone, that is a product bug — tell us which tap.
