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

Install + watch it live:
```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb install -r "dist\BNS-android.apk"
& $adb logcat -c                              # clear old logs
# launch the app on the phone, then:
& $adb logcat -d *:E flutter:V | Select-Object -First 80   # errors + flutter output
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

REAL since 2026-08-17 (it was documented here before the Dart had it —
and a Windows test seed overwrote the live store through shared
Documents). Both spellings work (`--data-dir PATH` / `--data-dir=PATH`),
and so does an environment variable:

```bash
BNS_DATA_DIR=~/bns-test-l4 open /Applications/bns.app   # macOS
```

A pinned instance never reads or writes the live `bns_home.txt` pointer
— the harness is isolated by structure, not by care.

## Same-Mac discovery when UDP 42424 never binds (2026-08-17)

Lived: every BNS on one Mac had TCP up (42425–42428) and UDP 42424
unbound. No Local Network prompt. לחבר showed «אין מכשירים חדשים»
because hello never left and `isRunning` meant "UDP is up".

Now `start()` opens TCP first, then tries UDP 42424 (reusePort, then
without). A failed hello is not fatal — the app stays up and knocks
`127.0.0.1` plus this machine's IPv4s on TCP 42425–42432 with `WHO\n`.
A sibling answers `WHO <id> <port> <name>` and appears for לחבר / a
code. Trust is never copied; L2 is not paired onto L4. Rebuild the L2
harness from this tree before re-testing.
Each knock reads one line or 600ms and always closes — a hung old door (stock / L4) must not hide a same-Mac sibling, including 127.0.0.1.
`start()` must not wait for UDP before the knock or before Sync listens; לחבר / חפש שוב re-reads peers already found. Rebuild the L2 harness (not L4, not הגדרות).

## 2026-08-17 ~06:37 IDT — L2 live (Caregiver watched, did not write the day)

Person (L2 isolated, paired to L2 Care, last sync 06:37):
- עוד היום stuck: water timeByDay 2026-08-17 → 17:30 (usual 16:00 stays)
- Skip reason stuck on eat: log 06:35 «משהו הפריע. שכחתי באמצע ולא חזרתי.»
- Tomorrow book they only LOOKED at (event 2026-08-18 16:00 still there)

Need-help they named: could not reach the doors on the screen. Too many steps. Had to write it into the day. Still open.

Care miss (pair holds, trusted רמה 2, last sync 06:37): Care still has 0 routines. Inspector cannot see their day. Receive-first is empty. Not L4. Not הגדרות.

**Fixed same morning (rebuild L2 Person + L2 Care, then sync — do not unpair, do not open הגדרות, do not write the day).** Root cause: the L2 care window hard-coded an empty `routines` list, so family-tagged / need-help routines (6 + 1 of the 8) never left Person; events and family moments did arrive. A leftover empty Care-profile door (minted from a seed thought) is no longer treated as a person and cannot block adopting the real one. The inspector now repaints when sync revises the store. Private untagged routines stay on Person. Care-empty merge cannot wipe Person (additive). Trust is not copied the wrong way.

## 2026-08-17 ~06:50 IDT — L2 live (Empty-Care-day fix 49281ac)

Empty-Care-day fix 49281ac worked. Isolated L2 only. Pair held. Person 8 routines; private ישיבה שקטה 20:00 untagged on Person only. Care sitting רמה 2 has 7 family + need-help; eat skip + water timeByDay 17:30 came through. Inspector: Mon 17 Aug, 0 נעשו · 7 ברשימה היום. Not L4. Not הגדרות.

REQUIRED, not shipped: **One Care / few people** (switcher, sit the right person). After 49281ac the L2 Care inspector shows an אנשים dropdown sitting on רמה 2. Early profile chrome, not a switcher. Still one Care / one trusted[] / one list. Multiprofile stays REQUIRED until one seat can follow a few people without a cloned app. Do not claim the dropdown is the switcher. Care boot sits on a profile (רמה 2) while caregiver/bns_data.json itself is empty. Do not start the switcher.

## 2026-08-17 ~21:32 IDT — L1 live on S23 (Caregiver watched, did not write the list)

APK still **0.11.0**. No pair. No extra BNS. No Guided/Full care. Sync friend still named Care, offline since 15 Aug 23:50 — do not tap לחבר. Do not send them to הגדרות. S23 still needs a current APK.

- הבא at night still תרופות הבוקר 21:45 part 1/3 (drink water before the pill), labeled "too late". Soft morning stack all still open (breakfast 07:30 through evening). Night and the next-goal rank are lying. Open.
- משהו הפריע still the old multi-door (later-remind + brown Save-this). Empty סגירה correctly did not skip.
- Calendar next day (Tue 18): banner «היום הזה עוד לא הגיע», no tick on that view. That door behaved.
- Keep: short note "peach 17" landed first on Memories.
- Menu ☰: 3 cards (מילות היום / השגרות שלי / הגדרות וסנכרון). Fine.
- They did not second-Done.

Known pile still live on this APK at 21:32 (expected old): Close-with-reason did not skip that pass, no «לא קרה» in the shade, Done asking again, too many Save doors. Later same night (~23:28–23:31) skip-Close lived — see 23:28 block.

## 2026-08-17 ~21:45 IDT — הבא walks the person-day (tree; needs a new APK)

Root cause: Next ranked by raw clock / most-overdue, so morning meds stole הבא at 21:32 while evening/night were still the real next. The 15:00-05:00 owl hole was already in the tree and unused by the hero.

After the day starts, a 07:30 breakfast is the next morning — visible, not הבא. A 04:00 owl slot is still tonight. No Settings door. Caregiver/L1 need a new APK (phone is still 0.11.0). Not L4.

## 2026-08-17 ~23:40 IDT — L2 person-day start 15:00 sticks

Lived on tonight's 0.11.0: day and pair stayed, עוד היום water 02:00→02:30 stuck, skip reason stuck, **dayStartHour 15:00 still showed 0**. They did not open הגדרות. A Care copy had already eaten 15:00 once today.

Root cause: the care window stub shipped shareName only (empty deviceId → merge ignored the clock), so Care stayed at midnight; Care then sent a full snapshot with `dayStartHour: 0` and last-write ate Person's 15. 0 meant unset and was treated as a real midnight.

Now: Sync has «מתי היום שלך מתחיל?» (not הגדרות). 15 survives save+reload. A helper / empty stub cannot midnight a set 15. The window carries the clock so Care learns 15 and עוד היום follows 15:00–end. Rebuild isolated L2 Person + L2 Care (not L4, not stock). Do not unpair. Do not write their day. Do not send them to הגדרות.

**L1 S23 ~23:28 IDT (APK 0.11.0, lastUpdate 22:07):** a8b1205 not enough on this device, or leftover 21:45. הבא still morning pills at night. Still open.

## 2026-08-17 ~23:28–23:31 IDT — L1 live on S23 (0.11.0 lastUpdate 22:07; Caregiver watched, did not write the list)

APK still **0.11.0** (lastUpdate 22:07). No pair. No extra BNS. No Guided/Full care. Do not tap לחבר. Do not send them to הגדרות. Not L4. Not הגדרות.

- הבא at 23:28 still 21:45 תרופות הבוקר — חלק 1/3 לשתות כוס מים / לפני הכדור, labeled "too late". Morning pills still Next at night. Midnight big card still morning pills. a8b1205 not enough on this device, or leftover 21:45. Open.
- משהו הפריע still the old multi-door (later-remind + brown Save-this + זה לא קרה היום + סגירה). Four miss doors when they only wanted write-why-and-close. Open.
- סגירה + "too late": skipped off Next. Words saved: לא קרה היום — נרשם + "too late" · 23:31. **Skip-Close lived on this 0.11.0** (left Next).
- New הבא jumped backward to 21:30 הכנה לשינה / לכבות מסכים while evening meds and family call still open. After skip the morning row still said הבא: לשתות כוס מים. Tile stayed; part line still drink water. Jump-back open.

## 2026-08-17 ~23:33 IDT — L2 live on 0.11.0 (Caregiver watched, did not write the day)

Day and pair stayed. Did not open הגדרות. Stayed on Today. Not L4. Not הגדרות.

- עוד היום: last water 02:00 → 02:30 today only. Override DID stick.
- Skip: desk, reason stuck — «התבלבלתי. יותר מדי שלבים. לא סיימתי.»
- Capture: kept words. Save / capture on screen still feels far. Still open.
- Tomorrow book: look-only, did not touch.
- Need-help maze: still cannot reach the doors on the screen. Too many steps. Have to write into the day. Still open.
- dayStartHour 15:00 still does not stick (shows 0). Day is supposed to start at 15:00. Open.

Caregiver same pass: they did not write the day. Family saw water → 02:30 and desk skip «התבלבלתי. יותר מדי שלבים. לא סיימתי.» Tomorrow look-only. Need-help still cannot reach the doors on 0.11.0. After isolated relaunch they will only look whether Care רמה 2 shows the skip and 02:30. This morning's 17:30 on water often failed to save — watch 02:30.

## 2026-08-17 ~23:50 IDT — leftover 21:45 cannot steal הבא (tree; needs a new APK)

22:07 APK **does** contain a8b1205 (`isNextMorningSlot` / `compareNextPersonDay` in libapp.so). Lived L1 at 23:28 still lost: dayStartHour 0 made 07:45 "in tonight", leftover 21:45 won as latest-past, skip walked backward to 21:30 screen-off, skipped stack kept הבא: לשתות כוס מים.

Root cause: startHour 0 was treated as midnight so the owl hole never fired, and earlier-today sorted latest-first so Next walked backward.

Now: unset start still treats a morning usual time as next-morning once evening has begun; leftover evening clocks on morning stacks cannot be הבא; Next walks the person-day forward (evening / family before 21:30); a skipped row drops the הבא part line. 04:00 owl is still tonight. L1 needs a new APK (emulator can take it). Not L4. Not הגדרות.

## 2026-08-17 ~23:52 IDT — person-day start door on Today

L2 after dce029b stayed on Today. «מתי היום שלך מתחיל?» lived only on Sync. They did not open הגדרות. Did not set 15:00. dayStartHour still 0. The door was too far from Today.

Now: the same kind line sits on Today under «היום שלך.» when dayStartHour is still 0 (the wiped default, not a chosen midnight). One tap 15:00 uses the same save as dce029b. After a real hour the door quiets — the day is 15:00, not a maze. No Settings. No Sync. No extra confirm.

Rebuild isolated L2 Person (Care only if the clock share needs it). They set 15. Do not write 15 for them. Not L4. Not הגדרות.

## 2026-08-18 ~00:05 IDT — unset 0 must not write 15 without a tap

Lived L2 Person rebuilt from 7d46b8d. Stayed on Today. Did not see «מתי היום שלך מתחיל?» well enough to tap. Did not open הגדרות. Caregiver did not write. dayStartHour 0 → 15 at 23:57:19 on Person; Care sitting learned 15 by auto-sync. L2: “I did not set it.” Do not reset their 15 (it is their day). Do not write 15 for anyone.

Root cause: the only store field that moved was dayStartHour (0→15), which is Today’s hour-chip persist. be5f435’s evening hole may *rank* as 15 when unset — it must not `updateSettings`. Care merge did not originate 15 (Care was still 0; it learned after). The door writes only on an explicit hour-chip tap. First paint / evening ranking with 0 stay 0. Tap 15 persists. No tap ⇒ still 0.

Rebuild isolated L2 Person to stop future auto-writes (Care only if the clock share needs it). Do not kill the running apps. Not L4. Not הגדרות.

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
