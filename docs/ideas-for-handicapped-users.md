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
- Modern application menu: persistent sidebar (NavigationRail style) with clean modern look.
- Selected items clearly marked with relaxing teal accent + highlight (same color scheme everywhere).
- More robust than mobile: generous typing areas, clear visual selection states, keyboard-first shortcuts that are set-and-forget.
- Keybinds: full user control with checkboxes ("ticking which keybind should be active"). Provide basic sensible layout (mark done, capture, diary focus, navigation) but never force the user. Edit combos freely. Saved inside the shared .bns file.
- Typing is #1 for PC user. Diary and capture fields are comfortable and focusable.
- PC can persist its own robust functions/config inside the .bns (keybinds, future desktop prefs) while fully compatible with phone/tablet sync.
- Same .bns format everywhere. LAN sync works cross platform.
- Same positive, forgiving, low-load UX.

## Android Widget Polish (current focus)
- Show "today's mission" (routines/goals for today).
- Let user see week plans from today if any.
- User sets how many days forward to see (stresses user otherwise). Default 2 (regular joe with severe brain injury doesn't like more than 2 days from now).
- Memories part of the story (we forget what we've done when making apps - final straw for building this for myself).
- Widget builds: user gets power, motivated, away from past, complete confidence in app (not afraid to use). We encourage a lot in the app.
- Positive, gentle, reliable.

## PC Flow Polish (July 2026 refinement pass)
Goal: gentler flow — celebrate first, offer second, never block a happy moment.

- ✅ **No more dialogs interrupting wins.** Completing a routine or saving a diary entry now shows one friendly toast with an optional action ("Remember this moment" / "Keep forever") instead of a blocking popup. Confetti plays uninterrupted; the offer waits quietly for 6 seconds and disappears if ignored. Low cognitive load, one primary action.
- ✅ **"Mark next step done"** (was "Mark something done"): completes the next *unfinished* routine, never re-toggles a finished one, and the toast names what was completed. If everything is done: "Everything for today is already done. Amazing!"
- ✅ **No duplicate navigation on PC.** The Today screen's bottom nav buttons (calendar/routines/memories) hide when the sidebar is visible; the duplicate sync icon in the app bar was removed. Mobile keeps the buttons.
- ✅ **Comfortable reading column** on wide monitors (Today content max ~780px, centered) — long lines are hard for brain fog.
- ✅ **Date always visible** in the PC top bar ("Saturday, July 5") — gentle orientation for memory support.
- ✅ **Keybinds that work + are discoverable**: Ctrl+D now truly focuses the diary field (not just navigate home); new Ctrl+T returns to Today; sidebar tooltips show each shortcut (Ctrl+R routines, Ctrl+M memories, Ctrl+N capture, Ctrl+, sync).
- ✅ **Empty Today state helps instead of stalling**: "Nothing scheduled for today — that's perfectly fine" + a button straight to Add Routine (the old text said "coming soon" even though the Routines screen exists).
- ✅ **Sidebar footer speaks to the user, not the developer**: "Everything stays on your devices. Private • No cloud • Yours."
- ✅ Diary description softened to "big or small, we applaud any progress" (same meaning, warmer words). Quick-win chips unchanged.

## Pass 3 — Keybinds for real, keyboard navigation, "I am mad" mode (July 2026)
Theme: structure to lean on. The marathon is insane — the app is the steady thing.

- ✅ **Keybinds actually work now.** The Sync & PC checkboxes used to be display-only; the app''s shortcuts were hardcoded. Now the shortcuts are built live from your saved keybinds: tick/untick applies instantly, combos apply instantly, and everything travels in the .bns. Central registry in `lib/core/keybinds.dart`.
- ✅ **Press-to-record combos.** No "ctrl+enter" syntax to type: click the combo, press the keys you want, see them written out, save. "Return to simple default layout" button always available.
- ✅ **Keyboard navigation of today''s steps**: Ctrl+G (default) jumps to the list, ↑↓ move a clear teal selection, Enter/Space completes (confetti and all), S opens skip-with-reason, Esc lets go. Hint line shown on PC.
- ✅ **New global actions**: mark next unfinished step done (Ctrl+Enter), save diary (Ctrl+Shift+Enter), go Today (Ctrl+T) — all remappable, all optional.
- ✅ **"I am mad" mode** — a pressure valve for rage days (rage is common in this community; it deserves first-class support, not silence):
  - "I''m mad" button on Today. One tap, no questions.
  - While on: header validates the anger ("It''s okay to be furious. This space can take it."), a warm-colored banner (errorContainer — same Material palette, semi-homogenous, not alarm-red chaos) offers **Vent now** — voice or text, curse like a rapper, zero judgment.
  - **Burnout built in**: the mode switches itself off after ~24h, and vents (tagged `mad-vent`) auto-delete within ~2 days no matter the retention setting. Anger gets space, not a permanent record. A vent deliberately promoted to "Memorize" is respected and kept.
  - Turning it off says: "Welcome back. Nothing you said is held against you."
- ✅ **Deliberate skip = win**: skip sheet now says "Skipping on purpose is a decision — and deciding counts as a win." A day without doing what you needed is okay; choosing is the structure.
- ✅ Fixed a broken brace in `isar_service.dart` that left all settings/keybind methods outside the class (file could not compile).

## Pass 4 — System repair: it builds everywhere now (July 2026)
Full discrepancy audit + repair. Details in `roadmap-and-brainstorm.md` ("Big repair pass").
Highlights for users:
- The app now actually compiles and packages on Windows + Android from this machine; iOS/macOS/Linux runner projects are complete and ready to build on their native machines. Same teal look, same .bns everywhere (semi-homogenous by construction: one Flutter codebase).
- Secure pairing became real and simpler to trust: the 6-digit code is TYPED on the second device, never sent over Wi-Fi. Decline is always one tap. Closed screen = automatic decline.
- Sync now truly encrypts both directions and refuses strangers entirely. Your device keeps its own name and identity even after imports.
- Reminders won't crash the PC version (Windows has no notification plugin support yet — gentle no-op there, sidebar date + Today screen carry the orientation load).
- Model tests protect the .bns format from accidental breakage.

## Pass 5 — Reference-wave absorption (July 2026, from the read-only idea inbox)
Workflow established: `C:\Dev\bns` is the read-only idea inbox (Grok drafts land there);
this folder is the state-of-the-art program. Ideas get ported here, implemented properly, and verified.

- ✅ **Per-device "LAN allowed" switch** in the trusted devices list — a calm kill switch: the device stays paired, but nothing flows either way until you flip it back. Default on, with advisory copy. Honored instantly by the running sync service.
- ✅ **Only .bns ever travels** — every LAN payload and every manual import is structurally validated (ZIP magic + manifest + data) before anything is processed. Hostile or broken files get a gentle "Not a BNS backup" message and go nowhere.
- ✅ **Desktop menu bar** (File / View / Help): export & import backups from the File menu, jump anywhere from View (with the keyboard shortcut shown), and a warm About box under Help. Discoverable like a proper modern PC app — friendlier than Office.
- ✅ Trusted-device cards redesigned: bigger targets, labeled switches (LAN allowed, Auto-sync), one clear forget button.

## Pass 6 — Industry-grade container (July 2026, reference wave 3)
"We are not toying around — solutions for an industry hungry for solutions, unbreakable."
- ✅ Container behind an abstraction: the .bns format can now evolve forever (faster codecs, deltas) without touching the app — old files always keep working.
- ✅ Unbreakable seal: every .bns carries SHA-256 integrity for its data and every voice note; a single flipped bit is rejected with a kind message and nothing partial ever reaches your data. Proven by test.
- ✅ Measured, not guessed: benchmark in CI — packing a heavy 5.9MB dataset: 151ms; unpacking with full verification: 74ms. Regression ceilings fail the build if it ever gets slow.
- ✅ Double-click .bns on Windows: `scripts\register-bns.ps1` registers the association (per-user, no admin needed).
- ✅ "Keep a ready-to-share .bns fresh" toggle in Sync & PC (on by default) — the seamless imaging is now user-controllable.
- ✅ After a crash or force-kill, the next launch says one calm line: everything was already saved as you went. Nothing lost. (True by architecture — per-change atomic saves.)
