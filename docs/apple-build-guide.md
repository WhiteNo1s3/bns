# Apple builds — the first hour on the new Mac (and what's already done)

**The honest rule first: iPhone/iPad/Mac apps can only be COMPILED on a Mac.**
Xcode runs only on macOS — no Windows tool can produce a real iOS build.
That is Apple's wall, not ours. BUT: everything that can be prepared from
Windows **is already in this repo** — the Mac day is assembly, not carpentry.

## Already done (nothing to configure on the Mac)

- `ios/` and `macos/` runner projects: complete, committed, build-ready.
- `.bns` file association on both (open a .bns from Files/Mail/AirDrop/Finder
  → BNS opens and imports; exported type `com.whiteno1se.bns`).
- Permission texts (mic, speech, local network for LAN sync) — gentle,
  person-facing, already written.
- Hebrew + English declared (`CFBundleLocalizations`).
- macOS entitlements: LAN sync both directions, mic, user-selected files —
  sandboxed properly (App Store-compatible).
- Reminders/notifications: the same gentle reminders as Android ride the
  Darwin notification path (init fixed for macOS; permission asked kindly on
  first run).
- iPad: same iOS build serves iPhone AND iPad (all orientations declared);
  wide screens get the sidebar layout automatically.
- The happy green brain icon is generated for iOS and macOS
  (`flutter_launcher_icons`, config in pubspec.yaml).
- `scripts/build-apple.sh` — the one script to run.

## The first hour, in order

1. **App Store → install Xcode** (big download; start it first).
2. Terminal:
   ```bash
   xcode-select --install                # command line tools
   sudo xcodebuild -license accept
   brew install cocoapods                # or: sudo gem install cocoapods
   ```
   (No Homebrew? Install from https://brew.sh first — one paste.)
3. **Install Flutter for macOS**: https://docs.flutter.dev/get-started/install/macos
   then `flutter doctor` until the Xcode row is green.
4. Clone the repo and build:
   ```bash
   git clone https://github.com/benshaltiel/bns.git && cd bns
   ./scripts/build-apple.sh
   ```
   That alone produces:
   - `dist/BNS-macos-v<version>.zip` — the Mac app, ready to use/share
   - an iOS build waiting for a signature (next section)

## Your iPhone — the one thing that needs YOUR Apple ID

Apple requires every app on a real iPhone to be signed by a person:

- **Free Apple ID** (works today): open `ios/Runner.xcworkspace` in Xcode →
  Runner → Signing & Capabilities → Team → sign in with your Apple ID →
  plug the iPhone in → Run ▶. The app installs and works — but a free
  identity expires after **7 days**; re-running from Xcode refreshes it.
  Fine for QA, not for living on.
- **Apple Developer Program ($99/year)** — the real path for BNS as a
  premium store app anyway: signatures don't expire, **TestFlight** lets
  family/testers install with a link, and the **App Store** is where the
  paid launch happens. Enroll at developer.apple.com when ready; nothing in
  the repo changes — Xcode just uses the paid team instead.

The same signed build covers **iPad** — one app, both shapes; wide screens
get the sidebar.

## The Mac app itself

`build-apple.sh macos` gives a clean native `.app` (Apple Silicon + Intel) —
the full experience, no PC limits: sidebar, keybinds, LAN sync, reminders,
.bns double-click. To use it on your Mac: drag `bns.app` to Applications.

Sharing the zip outside your own Mac: without notarization, macOS makes the
first launch a right-click → Open (once per machine). Notarization (removes
that step) comes free with the paid developer account: archive in Xcode →
Distribute → Direct Distribution.

## Versioned releases for GitHub (when the time comes)

One release per app version, every platform's file named the same way:

```
BNS-v0.11.0-android.apk       (certified: scripts/make-keystore.ps1 once, then scripts/build.ps1 -Target android)
BNS-v0.11.0-windows-x64.zip   (scripts/build.ps1 -Target windows -PackageWindows)
BNS-v0.11.0-macos.zip         (scripts/build-apple.sh macos)
```
iPhone/iPad never ship as files on GitHub — Apple only installs via
Xcode/TestFlight/App Store. When the store day comes, the same project
archives and uploads from Xcode.

Bump `version:` in pubspec.yaml before a release; every script stamps its
artifact from there.

## First-run QA on Apple devices (five minutes)

- iPhone: allow notifications when asked kindly; allow **Local Network**
  (that's LAN sync finding your PC — nothing leaves the Wi-Fi).
- Set a routine 2 minutes ahead → lock the phone → the gentle reminder
  should arrive, in your chosen color style.
- Open a `.bns` from Files → BNS should offer the import.
- iPad/Mac: rotate/resize — sidebar appears wide, simple flow narrow.
- Sync: Mac + iPhone on one Wi-Fi, Sync screen open → pair with the code.
