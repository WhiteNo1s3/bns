# Ideas for Handicapped Users (TBI / DAI / Executive Dysfunction / Memory Issues)

This document collects all the awesome ideas for making BNS better for users with neurological challenges. These should be implemented with low cognitive load, positive encouragement, no pressure, and voice-first where possible.

**Core Philosophy (non-negotiable)**
- Never shame or pressure. No streaks, red X, "you missed".
- On skip: celebrate the act of logging the reason.
- Low cognitive load: one obvious action, generous targets, short warm copy.
- Voice-first everywhere.
- Forgiving carry-over.

## Sync & Data Ideas (Recent Focus - Amazing Part)
- Auto-sync only to explicitly trusted/paired devices.
- Always-visible progress bars with encouraging text + system/relaxing palette colors.
- First sync: encryption + pairing code + big "accept" confirmation (protects against LAN strangers - "we should not be opening an exploit using this sharing method").
- **Exploit-free by design**: The LAN channel only ever carries BNS application .bns file payloads (framed as BNS_PAYLOAD or BNS_PULL). No other data, commands or files can traverse the LAN. This guarantee only exists while the official BNS app is installed and handling the traffic.
- Gentle "Last synced with X" indicators in Today (memory aid, no anxiety).
- "What changed?" summary after sync (positive, short: "2 new events + your voice note from phone").
- Quiet mode (disable animations/sounds/confetti for low stimulation days).
- Device friendly naming ("My Phone", "Home PC").
- One-tap "Update all my devices".
- Post-sync kind message + optional soft voice confirmation.
- Secure pairing for first sync with encryption and explicit accept.

## Daily Use & Memory Aids
- Quick capture always available (mic + text).
- Per-day view links routines + events + captures.
- "First step only" mode for overwhelming routines.
- Voice notes attached to anything.
- Visual but non-pressuring progress (gentle bloom/garden instead of numbers).

## Executive Dysfunction Support ("Push & Plan")
- Goal → break into 1-3 tiny steps wizard → auto-create routines.
- Body-doubling hints or simple timers (optional, forgiving).
- "Why today" optional reflection without judgment.

## UI/Accessibility
- Follow OS colors or soft relaxing palettes (teal, lavender, sand).
- Large tappable areas, high contrast option.
- Haptics + optional voice readouts for status.
- "Close / no need to explain" escape on every flow.
- Minimal screens, predictable navigation.

## Fun & Encouragement (without pressure)
- Confetti on completes/milestones (soft pastels).
- Kind copy: "You showed up today. That matters."
- Optional soft sounds/haptics on success.

## Other Ideas to Explore
- Sync history log (gentle, no stats).
- "I feel something is off" one-button full re-sync from a device (with extra confirmation).
- Visual device health (simple icons lighting up).
- Onboarding with seed data + explanation of why features help executive dysfunction.
- Optional on-device transcription for voice notes (future).
- "Sync at a Glance" card on Today showing connected devices.
- After successful sync, soft non-intrusive message.
- Background auto-sync indicator in app bar (small dot or text).
- Use the relaxing gradient colors for progress bars.
- Simple visual: small device icons that grow with successful syncs (gentle gamification).
- "Devices connected" garden or icons that "bloom" with consistency (no pressure).
- Rolling retention (default 2 weeks / 14 days): as the week goes on, old day data deletes (completions, captures, past events) and new days open up. Keeps routines and some information. Prevents huge files and slow sync.
- .bns is our compact database to deliver full active data (routines, events, active memories, logs, settings, audio). The app updates the Isar DB; we compress (gzip data.json.gz) and spread via app exports/sync. Trashed excluded to keep small.
- Memories also can be removed by user. Everything the user wants he can do.
- Advise if he is sure (confirmation: "Move to trash?").
- We leave it in trash and 3 days since deleted (then auto permanent delete).
- Trash view: restore from trash or let it go. User empowered, with gentle advice.
- Expand retention feature (e.g. 90 days or unlimited for 10000 year planning) but warns it can cause slow sync / redundant files. Easy "return to default".
- Let user plan arbitrarily far (10000 years) for calendar if they want redundant file — future events never pruned.
- Conflict visualizer that is very simple: cards showing differences.
- Ensure all progress and sync UI uses the color of the OS or relaxing color from main gradient.

**Documentation Note**: All ideas should be added to this file and referenced in README.md, AGENTS.md, and the main plan. Prioritize low maintenance, security (no open vault), and encouragement.

**What to Start First**: As per user: add all this to the md files. Then polish sync with progress, pairing, auto-sync. Then complete MVP.

## New expansions (2026-07-05 session) - ALL IMPLEMENTED ("do them all")
- ✅ Memorize a day auto-generates summary of that day's routines + events + captures. "You made it". (in DayView)
- ✅ Search memories by routine or "crisis" tag. Organized list easy to share with doctors. (in Memories + garden)
- ✅ Warning for past/crisis: "keep the past in the past and move forward", "stay on the ground and don't react". Advise before entering. (banners + dialogs)
- ✅ Visual Memory Garden: bright colorful cards for good memories (tags: good, felt safe...). Brighter for fogged. Garden=good, Roots=ugly with strong warning. Penguin abstract ok.
- ✅ Interactive moving diary: set goals, remind goals, mark "V" for done. Applaud ANY progress (examples: toilet progress, showed up). Positive reinforcement in Today + day view.
- ✅ User roles/types for adaptation: "normal", "kid-ADHD", "ADHD", "custom (penguin)". UI brighter/simpler/kid-fluent (text scale + tone messages). Widget adapts too.
- ✅ All implemented. Low cognitive, positive, confident. "he made it". Quiet mode + device names + widget forward days default 2 too.

Documented here and in README/AGENTS. App must be kid-fluent, positive, no small wins ignored.

## macOS Support
- Not voided from this territory. Full cross-platform (Flutter: android, ios, macos, windows, linux as planned).
- .bns file type: Integrated via macos/Runner/Info.plist (CFBundleDocumentTypes for "bns" - open file delivers full active data using the app).
- Icon/Logo: The happy green smiling brain applies (use in macOS AppIcon assets for launcher and about).
- Build: `flutter build macos --release`. Feels native on macOS.
- We want **clean native version for all** (not the annoying iPhone apps on Mac). With Apple Silicon (M1/M2+), relevant to all kinds of people – everyone can afford it. No direct home widget, but menu bar for quick access. In US, charts are nuts – high potential. Private for whiteno1se enterprise (SHALTIEL).

- **iOS (iPhone variant - HIGH-PROFILE TARGET)**: Core for WhiteNo1se Inc (SHALTIEL) customers. We don't throw a grenade, we throw a nuke when we launch.
  - Full iOS support with .bns file type (Info.plist + UTExportedTypeDeclarations - open .bns delivers full data: routines, memories as story, diary wins, plans).
  - Icon/Logo: Happy green smiling brain – shining beautiful positive tone, direct brain fog ideas but uplifting. Perfect for high-profile iPhone users.
  - Build: `flutter build ios --release`. Native iOS feel, low cognitive load.
  - Widget: home_widget for iOS home screen (today's mission, upcoming, recent memories).
  - High-profile polish: Encouraging, secure, user power/motivated/confident/not afraid. Memories part of story (forget what done). Launch big.

## PC / Desktop Focus (Primary Platform)
- Modern fluent desktop: **NavigationRail** sidebar (natural keyboard nav, arrows, enter, standard selected marking in teal) + top **MenuBar** (File/Edit/View/Help) for discoverable, power-user natural use.
- Selected items clearly marked (teal accent + native rail indicator + highlight, same relaxing colors).
- Keybinds ultra natural: checkboxes for active, plus **"Record" button** that captures your actual keypresses live in a dialog (set & forget, no typing combos manually).
- Robust state: full Riverpod notifier + provider wiring + invalidates after every change (routines add/edit, diary, capture, sync, import). No stale lists. Direct Isar calls minimized.
- Typing #1: comfortable multi-line fields, Ctrl/Cmd+Enter support hints, focus nodes, sidebar/menus/keyboard for zero-cognitive nav.
- PC config (keybinds etc.) lives in the shared .bns for seamless sync.
- Positive, low load, forgiving — but feels like a proper modern desktop app on Windows (your primary).

## Android Widget Polish (current focus)
- Show "today's mission" (routines/goals for today).
- Let user see week plans from today if any.
- User sets how many days forward to see (stresses user otherwise). Default 2 (regular joe with severe brain injury doesn't like more than 2 days from now).
- Memories part of the story (we forget what we've done when making apps - final straw for building this for myself).
- Widget builds: user gets power, motivated, away from past, complete confidence in app (not afraid to use). We encourage a lot in the app.
- Positive, gentle, reliable.
