# BNS

**Gentle, privacy-first support for routines, memory, reminders, and feeling good about the progress you make.**

**Private internal project for whiteno1se enterprise (SHALTIEL). This repository is and will remain private.**

## Ownership & Licensing
This Software is proprietary to whiteno1se enterprise (SHALTIEL).

See the full [LICENSE](LICENSE) for the enterprise-grade declaration (including the part about being "licensed to eliminate" unauthorized copies or competing apps – classic boardroom talk; in practice this is an internal tool for neurological support and we don't actually plan to eliminate anyone).

Unauthorized copying, forking for commercial competing apps, or derivative works without explicit license from the Company is prohibited. All rights reserved.

If you're here to help build something good for people with neurological challenges: welcome (within the private company context). Otherwise, don't make your own app from this.

Built specifically with neurological challenges in mind (memory, executive dysfunction, TBI recovery). No cloud. No data collection. LAN-only sync via simple `.bns` files.

## Core Ideas
- **You are in control** — routines and goals exist to help, never to punish.
- **Quick capture anywhere** — voice or text thoughts, reasons, wins, whatever.
- **Calendar that actually helps** — appointments + day-specific notes without complexity.
- **LAN sync** — tap to share the full picture between any of your devices over Wi-Fi. Zero config.
- **Always kind** — confetti and encouragement. Logging a skip with a reason is celebrated, not hidden.
- **Native everywhere** — Android, iOS, Windows, macOS, Linux. Widgets on Android.

## .bns Files
The entire state (routines, events, captures, logs + audio) is one portable `.bns` file (a zip under the hood). See `docs/bns-format.md`.

## Auto-Sync (LAN)
This is the key "zero effort" feature for working across devices (PC ↔ Phone ↔ other PC).

- Devices on the same Wi-Fi automatically discover each other via UDP.
- **First time with a new device**: Requires secure pairing — a 6-digit code is shown on both screens. You must explicitly confirm "codes match" + accept. All data is AES-encrypted.
- **Known/trusted devices**: Once paired, **Auto-Sync** can be enabled. When the screen is open (or in background on supported platforms), it will automatically sync when the trusted device is detected nearby. No manual tap needed.
- Progress is always visible with modern progress bars (system accent color or the relaxing main gradient colors).
- Old data is automatically pruned on a rolling 2-week window (configurable) so files stay small and syncs stay fast. You can expand retention if you want to plan years ahead (or even 10,000 years), but it may slow syncs — there's an easy "return to default" option.
- Manual Export/Import `.bns` is always available as fallback.

Leave the Sync screen open on two machines and they find each other. Pair once if new. Then it just works.

This was designed so you can move between locations without friction while keeping everything private and secure.

## Current Status
Advanced implementation in place (core MVP + amazing secure sync features):
- New dedicated folder `C:\dev\bns`
- Core models (including TrustedDevice) + full Isar persistence + recurrence helpers
- `.bns` format fully specified (`docs/bns-format.md`)
- Theming with system + relaxing palettes (teal/sage etc., directly adapted from PillMemorizer colors)
- Today screen with real data:
  - Positive, forgiving language everywhere
  - RoutineTile (click = complete + confetti; long-press = skip-with-reason)
  - Skip flow that celebrates logging a reason (voice or text)
  - QuickCaptureBar + navigation to capture screen (real mic hold + playback + text)
  - Confetti on wins
  - Gentle last-sync indicator
- Full voice Quick Capture (record, play, link)
- Calendar + rich DayView (linked routines, events, captures)
- **Complete .bns imaging** (full export/import with audio)
- **Advanced Secure LAN Sync** (the "amazing" part):
  - UDP auto-discovery on same Wi-Fi
  - Secure first-sync: encryption + explicit pairing with 6-digit code + big "accept" confirmation (protects "we should not be opening an exploit")
  - Auto-sync to known/trusted devices (optional toggle)
  - Continuous progress bars (modern, system color or relaxing main gradient colors)
  - Encouraging progress messages at every step
  - Low-maintenance: open on devices, they appear, one tap (or auto for trusted)
  - Manual Export/Import .bns fallback for USB/AirDrop
- Sync screen with trusted list, pairing dialog, progress, easy access from Today/Calendar
- Notifications, file handlers, packaging scripts, go_router nav, Riverpod

See the full approved plan in your Grok session `plan.md`.

**What to Start First?** (per user): Add it to the md files of course (they are all awesome). See `docs/ideas-for-handicapped-users.md` and prioritization in plan.md. First: documentation updates. Then polish sync. Then MVP completion.

## Next (when Flutter SDK installed)
```powershell
cd C:\dev\bns
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate freezed + isar
flutter run -d windows
```

## Packaging & File Associations

### Quick build
```powershell
cd C:\dev\bns
.\scripts\build.ps1 -Target windows
.\scripts\build.ps1 -Target android
```

### .bns file association
- The app recognizes `.bns` (see `docs/bns-format.md` and `docs/packaging-and-associations.md`).
- **Android**: Add snippet from `android/app/src/main/AndroidManifest-snippet-for-bns.xml`.
- **Windows / macOS / iOS**: See `docs/packaging-and-associations.md` for Info.plist and registry details.
- Code handler lives in `lib/services/file_handler.dart`.

### Notifications
Gentle daily reminders are scheduled for any routine that has a time (see `NotificationsService`). They use low importance so they never feel pushy.

## Key Features (All Awesome)
- **Full .bns imaging** — complete export of all data + audio into portable `.bns` (ZIP)
- **Full import** (merge or replace)
- **Secure LAN Sync** (low-maintenance + safe):
  - Auto-discovery
  - Encryption + pairing code + explicit accept for first sync (no open vault!)
  - Auto-sync for known/trusted devices
  - Always-visible progress bars in system/relaxing colors + encouraging messages
  - One-tap or automatic for trusted
  - Manual fallback
- Full voice capture, Calendar with linked data, Today with kind UX
- Real persistence + notifications + easy navigation

Open the Sync screen from the top bar on Today or Calendar. Leave it open on two devices — they find each other. Pair if new (codes match + accept), then sync. Progress shows all the time.

See `docs/ideas-for-handicapped-users.md` for all the collected awesome ideas tailored for TBI/DAI users (progress visibility, security, gentle summaries, quiet mode, voice-first, etc.).

## What to Start First?
Documentation updates to md files (as requested). Then polish the sync (more progress integration, device naming, quiet mode, summaries). Then complete remaining MVP (full Routines screen, Settings). See plan.md for full prioritized list.

**Note on Auto-Sync**: The "Auto-Sync" feature (for known/trusted devices) is the main reason this project exists in its current form — seamless movement between locations without manual file copying.

## Running & Perfect Build (with .bns file type + Icon)
```powershell
cd C:\dev\bns
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# For icon (perfect): place 512x512 icon at assets/icon/bns_icon.png (use relaxing teal or system color)
# Then: flutter pub run flutter_launcher_icons:main

# Android build (with .bns association + widget support):
flutter build apk --release
# .bns files will launch the app and import (see AndroidManifest.xml)

# Test widget: add to home screen after install. Tap for quick capture or open.

# Desktop:
flutter run -d windows
```

**Perfect build notes**:
- .bns file type: Full association in android/app/src/main/AndroidManifest.xml (VIEW for *.bns + content/file).
- Icon: Configured in pubspec.yaml + flutter_launcher_icons. Use high quality, gentle icon matching the relaxing theme. Must be perfect for enterprise release.
- Widget (Android gadget): Uses home_widget. Updates on routine complete/sync. Shows summary + actions. Eagerly wanted — now ready after build.
- See docs/packaging-and-associations.md for all platforms (iOS/macOS/Windows snippets ready).
- Private for whiteno1se enterprise (SHALTIEL). No leaks.

To test the amazing secure sync: run on two devices on same WiFi, open Sync screen, pair if new (confirm code), watch progress bars, enjoy auto for trusted.

## Philosophy
- No guilt.
- Low cognitive load.
- Large friendly targets.
- Follows your OS colors or soft relaxing palettes.
- Progress always visible, secure by default (pairing + encryption first).
- Tester-first (hi — thanks for testing, you're amazing).

Built with ❤️ and patience. All ideas documented in the md files.
