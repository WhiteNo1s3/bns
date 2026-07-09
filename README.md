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
- **Android is the flagship** (pivot 2026-07-06) — widgets in bundles (today's mission, upcoming plans, quick actions), voice-first capture, dirt-simple screens. PC remains the fully-featured desktop experience (sidebar, keybinds, MenuBar) and every platform shares the same .bns files.
- **Calendar that actually helps** — appointments + day-specific notes without complexity.
- **No accounts, no cloud** — the 0.12a account-server pivot was cancelled the same day (see `prototypes/cloud-pivot/`). Devices share directly over the user's own Wi-Fi; `.bns` files are the by-hand backup; the web satellite is the no-install window.
- **Premium, paid-only** — no ads, no free tier, no subscriptions. Store purchase (~$1–2, final price pending) is the only distribution.
- **Always kind** — confetti and encouragement. Logging a skip with a reason is celebrated, not hidden.
- **Native everywhere** — Android, iOS, Windows, macOS, Linux. Widgets on Android. PC feels like a real modern application.

## .bns Files
The entire state (routines, events, captures, logs + audio) is one portable `.bns` file (a zip under the hood). See `docs/bns-format.md`.

Credit where due: the container is the open ZIP format (PKWARE's "zip magic") with DEFLATE/GZIP compression and JSON data — open technology used as-is, no ownership claimed. What makes a `.bns` a `.bns` is our identity layer on top (EPUB-style `mimetype` marker first in the archive, `application/x-bns`, at a fixed byte offset), so the file is instantly recognizable as ours while staying transparently inspectable with any archive tool.

## The Explorer (`satellite/bns-web.html`) — for the people AROUND the user
One static HTML file = a .bns explorer in any modern browser: **observe the
data and sync files to the computer** without installing anything. It's meant
for people who don't use BNS constantly — non-users, kids, loved ones — while
the user himself lives in the native program (Windows/Android). Open a .bns,
see routines/calendar/memories/diary, play voice notes, make edits, save a
re-sealed file back to the computer. **No server, no npm, no install, no
account, no network calls, no traces.** Double-click it locally or host it on
the website as a plain static file; on iPhone, Safari → Add to Home Screen
makes it an app-shaped door with zero App Store involvement.

Two special powers: it auto-opens **family share** files (`BNS_Family_*.bns`)
into a read-only "important plans" view, and `#family` shows any full backup
as a gentle read-only window. It is the second official implementation of
both .bns containers, cross-verified against the app's Dart packers by
`tool/cross_check.dart`. (The no-server law stands: this is a document tool,
not a service.)

## Why Flutter (and not five native apps)
One codebase carries the entire product — the sync protocol, the sealed .bns
packers, mad mode, the kindness — to Android, iOS, Windows, macOS and Linux,
compiled AOT to native machine code. Native is used exactly where it matters:
the Android widgets are hand-written Kotlin, file associations are native
manifests, speech uses the device engines. A ground-up native rewrite would
cost months and buy nothing users can see; the real lock-in insurance is the
.bns format itself, which already has two independent implementations (Dart
and the satellite's JS) — any future app on any stack can speak it. Full
decision record in `docs/roadmap-and-brainstorm.md`.

## Working from multiple computers (GitHub)
The source of truth is the private repo `github.com/benshaltiel/bns`.
On any machine (including the Kubuntu laptop):
```bash
git clone https://github.com/benshaltiel/bns.git
cd bns
flutter pub get
flutter test          # 18 tests incl. container benchmark + tamper checks
flutter build linux   # on the Kubuntu laptop (needs: clang cmake ninja-build \
                      #   pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev)
```
Built artifacts (`dist/`, `build/`) stay OUT of git — rebuild them anywhere;
releases ship binaries, the repo ships source. Commit + push at the end of a
session, pull at the start of the next, whichever machine you're on.

## Auto-Sync (LAN) — the main road (re-affirmed after the cancelled 0.12a server pivot)
PC ↔ Phone ↔ other PC on one Wi-Fi, no third party in the middle.

- Devices on the same Wi-Fi automatically discover each other via UDP.
- **First time with a new device**: Requires secure pairing — a 6-digit code is shown on both screens. You must explicitly confirm "codes match" + accept. All data is AES-encrypted.
- **Known/trusted devices**: Once paired, **Auto-Sync** can be enabled. When the screen is open (or in background on supported platforms), it will automatically sync when the trusted device is detected nearby. No manual tap needed.
- Progress is always visible with modern progress bars (system accent color or the relaxing main gradient colors).
- Old data is automatically pruned on a rolling 2-week window (configurable) so files stay small and syncs stay fast. You can expand retention if you want to plan years ahead (or even 10,000 years), but it may slow syncs — there's an easy "return to default" option.
- Manual Export/Import `.bns` is always available as fallback.

Leave the Sync screen open on two machines and they find each other. Pair once if new. Then it just works.

This was designed so you can move between locations without friction while keeping everything private and secure.

## Current Status
Advanced implementation in place (core MVP + amazing secure sync features + all polish "do them all"):

- All major features complete: routines, calendar+day+auto day summary memorize, quick voice capture, LAN sync with pairing+progress+auto, .bns gzip compact, rolling retention, trash 3d, full memory garden+roots+search+crisis tags+ past warnings, interactive diary with V small wins, user types (normal/kid-ADHD/ADHD/penguin), adaptive BnsAppBar native iOS/mac clean, Android widget with configurable forward days (default 2), positive everywhere (confetti, messages, you made it), quiet mode.
- User types adapt UI scale/tones (brighter kid fluent etc.).
- Quiet mode, device naming, full import on .bns open.
- Positive, low load, forgiving, no guilt. All ideas from docs implemented.
- PC flow polish pass (July 2026): no blocking dialogs after wins (toast + optional action instead), "Mark next step done" completes the next unfinished routine, no duplicate navigation on desktop, comfortable reading column on wide monitors, date in top bar, working Ctrl+D diary focus + Ctrl+T Today, shortcut hints in sidebar tooltips, helpful empty state. See `docs/ideas-for-handicapped-users.md` → "PC Flow Polish".
- Keybinds + keyboard + mad pass (July 2026): keybinds are now LIVE (built from settings, tick to enable, press-to-record combos, travel in .bns), full keyboard navigation of today's steps (Ctrl+G, ↑↓, Enter, S), and **"I am mad" mode** — a judgment-free rage valve: vent in any language you want, vents burn out within ~2 days, the mode calms itself after ~24h. Deliberate skips are celebrated as decisions. Roadmap + parked ideas now tracked in `docs/roadmap-and-brainstorm.md`.
- **It builds now** (July 2026 repair pass): real platform runners for Windows/Android/iOS/macOS/Linux with .bns associations, permissions and entitlements in place; Isar/freezed replaced by a dependency-free JSON snapshot store (same API, no codegen); LAN sync protocol + secure pairing actually work (stable device identity, real encryption both ways, type-the-code pairing); `flutter analyze` clean, model tests passing. Full list: `docs/roadmap-and-brainstorm.md` → "Big repair pass". iOS/macOS build on a Mac; Linux on a Linux box; no web target by design (dart:io, privacy-first native).
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

### PC Desktop (Primary)
- Modern sidebar navigation (clean, selected items highlighted with the teal relaxing colors).
- Keybinds: Go to Sync screen → scroll to "PC Keybinds". Checkboxes to enable/disable, edit the key combo (e.g. `ctrl+enter`). Set & forget. We ship good defaults + simple grouped layout so it's easy. Not mandatory.
- PC-specific data (keybinds, future robust features) stored inside the normal .bns — full sync compatibility, mobile just carries the fields.
- Typing optimized: big diary fields, focus shortcuts, comfortable capture.
- More robust lists and selections than mobile views.

**What to Start First?** (per user): All done! ("do them all"). Polish complete, user types, garden, diary V, widget, warnings, summaries, clean native iOS/mac bars, quiet, more encouragement. See docs. Run on devices for LAN sync test.

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
- **.bns is our compact database** to deliver full active data (routines, events, active memories/captures, logs, settings, audio). App updates local DB; .bns is gzipped (data.json.gz) for compactness, spread to users via app. Trashed excluded.
- **Full import** (merge or replace)
- User control: memories (and data) can be removed. Confirm if sure. Trash holds 3 days then auto gone. Full empowerment.
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

**"do them all" complete**: user types adapt (scale + tones for kid/ADHD/penguin), memory garden + roots + past warnings + crisis search, auto day memorize summaries, interactive diary + V marks + small wins, widget polish (today mission + N days default 2 + memories), quiet mode, device names, clean native iOS/mac via adaptive bar, full .bns import on open, more encouragement, docs updated. All low load + positive.

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

# iOS (HIGH-PROFILE iPhone - nuke launch for WhiteNo1se Inc (SHALTIEL)):
flutter build ios --release
# .bns association (Info.plist) for full data. Icon: happy green brain.
# No extra installs.

# macOS clean native (not iPhone apps on Mac, Apple Silicon relevant/affordable for all):
flutter build macos --release
# .bns association (Info.plist) for full data. Icon: happy green brain. In US charts are nuts - high potential.
# No extra installs.

# Desktop:
flutter run -d windows
# Self-contained, no extra for PC. Use platform tools.
```

**Perfect build notes** (must be perfect):
- .bns file type: Full association in android/app/src/main/AndroidManifest.xml (VIEW for *.bns + content/file). App launches and imports automatically. Desktop associations via snippets + build.
- Icon & Logo: The happy green smiling brain! This is it — fits every angle. Direct brain fog ideas with a shining, beautiful, positive happy tone. Not directing or clinical, just supportive and uplifting. Green smiling brain for the icon (launcher/adaptive), logo version integrated. Perfect for severe neurological damage management with happy encouraging vibe.
  - bns_icon.png and bns_logo.png in assets/icon/.
  - Configured in pubspec.yaml + flutter_launcher_icons (teal adaptive bg from relaxing palette).
  - Run `flutter pub run flutter_launcher_icons:main` for generation.
- Widget (Android gadget - polished): Uses home_widget. Shows "Today's mission" (due routines/goals), plans for next N days (user-configurable 0-7, default 2 - regular joe doesn't like to know more than 2 days ahead to avoid stress), recent memories/wins (part of the story, since we forget what we've done when building). Positive encouragement like "You showed up. Small steps = big wins. You got this!". Updates automatically. Tap to open app or capture. Configurable in Sync screen. Builds user power, motivation, confidence, and distance from past.
- Build: `flutter build apk --release` (perfect with above).
- macOS: Fully supported (not voided from this territory!). We want **clean native version for all** (not the annoying iPhone apps on Mac via Catalyst or "Designed for iPad"). With Apple Silicon (M1/M2+), relevant to all kinds of people – everyone can afford it. Clean native build, .bns support, happy green brain icon. Feels like a proper Mac app. No extra installs needed. Use each device's own tools (no copy-paste). Apple ecosystem trash per user, but we polish iOS/mac clean native.
- iOS: High-profile iPhone target. Clean native (not relying on Mac compat). .bns, icon, build perfect. No extra for users.
- **iOS (iPhone variant - HIGH-PROFILE TARGET for WhiteNo1se Inc (SHALTIEL) customers/users)**: We don't throw a grenade, we throw a nuke when we launch. Core focus.
  - Full Info.plist with .bns document types + UTExportedTypeDeclarations (com.whiteno1se.bns).
  - Open .bns on iPhone/iPad → app imports full active data (routines, memories as story, diary wins, calendar plans, etc.).
  - Icon/Logo: Happy green smiling brain – shining, beautiful, positive happy tone for brain fog/neuro management. Perfect for high-profile iOS. Configured for AppIcon.
  - Build: `flutter build ios --release` (IPA for TestFlight/App Store). Native iOS feel.
  - High-profile polish: Low cognitive load, encouraging, secure LAN sync, widget support (home_widget for iOS home screen). User gets power, motivated, away from past, complete confidence – not afraid to use.
- See docs/packaging-and-associations.md for all platforms (Android, iOS, macOS, Windows, Linux).
- Private for whiteno1se enterprise (SHALTIEL). No leaks. Test file association by sharing .bns.

To test the amazing secure sync: run on two devices on same WiFi, open Sync screen, pair if new (confirm code), watch progress bars, enjoy auto for trusted.

## Philosophy
- No guilt.
- Low cognitive load.
- Large friendly targets.
- Follows your OS colors or soft relaxing palettes.
- Progress always visible, secure by default (pairing + encryption first).
- Tester-first (hi — thanks for testing, you're amazing).

Built with ❤️ and patience. All ideas documented in the md files.

## Credits

Built by [WhiteNo1s3](https://github.com/WhiteNo1s3). Released under the MIT License.

