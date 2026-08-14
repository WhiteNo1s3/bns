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

## Silk memories law (grokBNS, 2026-08-14)
A Level-1 user with cognitive reserve almost broke the phone because the app hid what they had just recorded.

- **If they recorded it, they see it.** `quick` / `remember` / `memorize` is how long something is kept — never a reason to hide it. Mad-vents stay hidden (sacred).
- Save always lands on **Your memories**. The newest thought is at the top.
- Today shows **What you kept** (last three) so a recording is not a disappearing trick.
- Capture has one job: speak or write, then Save. Extra choices sit behind "A little more".
- Phone: three doors — Today, Memories, Keep this. No hunting through tiny icons.
- Tap a memory: the words, the voice, Close. No warning quiz. No empty snackbar.
- Same law on every OS, including Mac. Same `.bns` file.

## Mac microphone + one day at a time (2026-08-14)
- Recording on Mac must use the **recorder’s own permission** (`record.hasPermission(request: true)`). `permission_handler` has no macOS plugin — calling it killed the tap, so the system never asked, and the mic never opened.
- Today’s routine tiles show **today only**. Notes and skips from other days live in the day diary and in Memories — they do not ride today’s row.

## One mic (2026-08-14)
Keep this = one microphone. It records the voice, then writes the words into the box under **הקלטה 1**, **הקלטה 2**… A new take always starts on a new line. The person edits, adds, plays the voice, and taps **להקריא את המילים** (Hebrew TTS). No second mic.

Wired on the must-have OSes (same button, same box):
- **Android** — records WAV; Hebrew words through the Waze door after stop; play + TTS.
- **Apple (iPhone + Mac)** — records WAV; on-device file ear writes the words; play + TTS.
- **Windows** — records WAV; Whisper (Hebrew) / Vosk (English) if installed on the Sync screen; play + TTS.

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

## Massive diary for neurological handicaps + STT on every comment (2026-07-26)

**Who this is for.** Phones are everywhere. BNS is the everyday diary for people whose cognition is damaged or fading: TBI (including people who never “got cognition back”), dementia, Alzheimer’s, executive dysfunction, memory loss. Specs already cover care levels 3–4, guided mode, family spectrum, voice-first capture. This pass names the **diary spine** and closes the hole where **comments had no working voice typing**.

### Product spine — the day IS the diary

Not a second “journal app.” Everything the person ticks, skips, rants, or says is a page:

| Kept thing | How it lands | Care signal |
|------------|--------------|-------------|
| Deliberate skip + reason | Completion log `reason` + optional `need-help` capture | Frustration is the signal (elevators, mornings, etc.) |
| Long-press “what got in the way” | Capture tagged `need-help`, linked to the routine | Same — remembered so help can arrive |
| Diary box on Today | Capture tags `diary` / `goal-progress` | Wins and hard things both belong |
| Quick capture / widget 🎤 | Voice note + optional text/transcript | Free thought channel |
| Mad vent | Tag `mad-vent`, burns out ~2 days | Sacred; never garden/summary unless Memorize |

**Massive** means chosen forever (memorize / garden), not infinite raw days. Rolling retention keeps the live phone light; deliberate “keep forever” is the deep archive. Streaming `.bns` already sustains large audio.

### Phone-first comment hierarchy (one obvious door)

Too many doors kill the feature for fog / late dementia:

1. **Primary:** tick done / long-press problem  
2. **Secondary:** big “Tell about today” (widget 🎤 + capture)  
3. **Tertiary:** diary box (hidden in guided mode — already)  
4. **Sacred:** mad mode vent  

On phone, comment paths should always allow **voice → words** without opening a different mental mode. Typing remains the safety net, never the only path.

### Care levels (unchanged law)

- **Normal:** list + diary + capture  
- **Full care (3):** caregiver sees all comments and audio (rants included)  
- **Guided (4):** list only; long-press + capture = only writing left to the person; inspector builds the day  

Never put diary *construction* on level 4. Words yes; planning no.

### STT law — “STT all the time” on comments (field truth)

- Device engine only (same privacy rules as TTS). No cloud STT, no AI-API subscriptions.  
- `DictationMicButton` is the building block for **every** person-facing text field that is a comment.  
- **Android:** never run STT *while* the recorder holds the mic (killed the note on the owner’s S23). Recording wins; words come **after** the voice is safely kept, or via dictation-only (no concurrent record).  
- **Windows:** post-file Vosk on WAV is the sequential path (no mic fight).  
- Hebrew locale ladder stays honest; missing language pack is said gently once, never silent dead mic.

### Gaps closed in this pass

| Surface | Before | After |
|---------|--------|--------|
| Today diary box | Type only | Dictation mic on the field |
| Long-press “what got in the way?” | Type only (or leave for full capture) | Dictation mic on the note field |
| Capture after Android record | “no words yet” unless user finds small mic | Gentle “Speak words for this note” once mic is free; still optional, never blocks save |
| Capture text / context | Already had mics | Unchanged |

### Next hero + Coming up (2026-07-27) — shipped
- ✅ **Clean Next card** on Today (relaxing `primaryContainer`, large type, one primary “It's done”, secondary “Something got in the way”). No stickers/busy decoration — fog first.
- ✅ Hero always ordered by clock “what's next”; full list below keeps morning→night or next preference.
- ✅ **Coming up** strip: next two open items only.
- ✅ Empty day: soft clear card; guided copy stays list-first.

### Day complete (wave 13, 2026-07-27) — shipped

- ✅ **Day diary thread** (`/day`): morning→night feed of done, didn’t-happen + reason, hard notes, diary lines, thoughts, plans. Search words and reasons. Static date change (no slide).  
- ✅ **Care glance** (full care only): soft “what to help with” lines for the week — never a scoreboard, never “you missed”, vents not headlined.  
- ✅ **Memorize-day auto summary** rebuilt on the pure feed builder — **mad-vents never enter**.  
- Entry points: Today “Today’s words”, desktop sidebar “Day diary” (Ctrl+Y), Day view book icon.

### Parked (don’t lose)

- **Offline file STT on Android** (transcribe after record without a second speak) — waiting on a privacy-safe engine path that doesn’t re-fight the mic model.  
- **Hebrew Vosk model** on Windows — optional mirror of English install.  
- **Doctor-share export** from the day thread / memories — vents always excluded.

### What we refuse

- Cloud STT / AI day summaries  
- A parallel journal product that doesn’t sync as `.bns` captures  
- Concurrent STT + record on Android without device proof  
- Streaks, “you didn’t write today,” red marks on empty diary days  

### Live test questions (add to session checklist)

- “Could you speak into the diary and into ‘what got in the way’ without typing?”  
- “After a voice note, was adding words easy — or did it feel like a second app?”  
- “Did the mic ever feel broken or silent for no reason?”  
- Existing AGENTS questions still apply (confusing? mad at you? LAN safe?).

## Reminders that actually arrive (level 1-2 wave, 2026-08-08)

Levels 1-2 are the independent people — reminders are the app keeping a
promise FOR them, so this wave is about reminders being real, kind, and
theirs.

### Shipped

- ✅ **They fire now (Android).** The scheduled-notification receivers were
  missing from the manifest, so every scheduled reminder was silently lost.
  Registered, plus the boot receiver — reminders survive a phone restart
  and an app update (a reboot must not eat a medication reminder).
- ✅ **Right days only.** A Tuesday routine reminds on Tuesday, not daily
  (per-weekday scheduling for weekly/weekdays/custom routines).
- ✅ **Plans get a heads-up.** Calendar events with a time remind before
  the moment — the person picks the lead: off / right on time / 10 / 30
  (default) / 60 minutes before. 14-day rolling horizon, capped so
  routines always keep room (iOS ~64 pending limit).
- ✅ **How loud is theirs to choose.** Quiet (waits in the list, silent),
  Gentle (default — soft chime), Bright (banner, hard to miss). Own
  Android channel per style so the system respects the choice.
- ✅ **Colored by the like of the user.** 'My app colors' follows the
  relaxing palette; or a gentle named color: teal, lavender, green, amber,
  rose, sky. Deliberately no red — a reminder is never an alarm.
- ✅ **Tap lands home.** A routine reminder opens Today; a plan reminder
  opens that day's page. Works from a closed app too.
- ✅ **Reminders follow the data by themselves.** Any change — an edited
  time, a new plan, a LAN sync, a .bns import — quietly refreshes the
  schedule (debounced, fingerprinted; no screen has to remember to ask).
- ✅ **Windows is not left out.** No system notifications exist for it yet,
  so while BNS is open a gentle in-app card appears at the moment, in the
  person's chosen color, with an Open button.
- ✅ **The helper's device stays silent** (caregiver law unchanged) and the
  master switch has a real UI now (Sync screen → Reminders).
- ✅ macOS/Linux init fixed (missing platform settings made notifications
  silently dead there).

### Where it lives

- `lib/core/reminder_plan.dart` — PURE planning (what should be scheduled,
  fingerprints, tap routes). Tested in `test/reminder_plan_test.dart`.
- `lib/services/notifications_service.dart` — turns the plan into real
  scheduled notifications (channels, colors, styles).
- `lib/services/desktop_reminder_service.dart` — the Windows in-app card.
- Settings fields: `reminderStyle`, `notificationColor`,
  `eventReminderMinutes` (see `docs/bns-format.md`).

### Live test questions (add to session checklist)

- "Did a reminder actually appear at the time — and after restarting the
  phone?"
- "Was the reminder's loudness what you chose — and did the color feel
  like yours?"
- "Did tapping it land you where you expected?"
- "On the PC, did the little card show up while the app was open?"

## Plans carry weight + Hebrew everywhere (2026-08-09)

**The word is PLAN (תוכנית) — never "task" (owner: the handicap must not
feel like handicap).** A doctor appointment, an errand, a one-time thing:
not a routine, but today it stands IN the day.

### Shipped

- ✅ **Plans sort into Today**: one-time calendar things weave into the
  day list by the same clock laws as routines (answered sinks, both order
  preferences honored). `lib/core/day_items.dart` (pure, tested).
- ✅ **Plans are answerable**: the same checkbox language — tap = "Is it
  done? 🌿", long-press = "didn't happen" with a kept why. Answers live on
  the plan itself in the .bns (`answer`/`answerReason`/`answerAt`).
- ✅ **Answered plans stop reminding** (scheduled + Windows in-app both).
- ✅ **Quick add on Today**: "A plan for today" — title + optional time,
  never forced into a routine. Also offered on the empty day.
- ✅ **Hebrew completeness**: the Android home widgets now speak the
  person's language (all summaries, empty states, "Tomorrow", progress);
  widget buttons/headers localized via Android resources (values-iw) — and
  "＋ Task" became "＋ Routine"/"＋ שגרה" per the no-task law; first-run
  seed routines Hebrew-first; user-type names translated; .bns import
  messages translated.

### Parked (don't lose)

- Plans in the NEXT hero card + "Coming up" strip (today they join the
  list only).
- Answered-plan ✓ shown in the calendar day view + day thread feed.
- Per-app language for widget buttons (today they follow the phone's
  language, which is right for almost everyone).

### Live test questions

- "Did your doctor appointment show up inside your day, in its place?"
- "Did ticking it feel exactly like ticking a routine?"
- "Is every word on the home widgets in your language?"

## Wave: silky sync (2026-08-09, owner QA in his own words: "sync is
## getting out of hand... I also want it silky")

### Shipped

- ✅ **The killer bug**: leaving the Sync screen disposed the app-wide
  sync singleton — discovery, transfers, and event streams all died until
  restart ("the pc couldn't see the device anymore"). Screens can no
  longer stop the service; it is a lifelong resident.
- ✅ **One-step pairing**: tapping Pair sends the request immediately —
  the other device asks for the code while the person is reading it. The
  deceptive "I typed it there — connect" button is gone. Honest failure
  copy + "Try again (fresh code)".
- ✅ **Mistyped codes get caught**: first sync after pairing pulls first
  and verifies the key; a mismatch says "the code didn't match on both
  sides", undoes the broken pairing on both ends, and offers a fresh
  start. No more silently-broken-forever pairings.
- ✅ **Pairing requests reach any screen**: the enter-code prompt is
  installed app-wide (main.dart), not only while the Sync screen is open.
- ✅ **Continuous auto-sync**: cooldown-based (10 min), not
  once-per-session; local changes push to nearby trusted devices ~4s
  after the edit (ping-pong-proof: changes that arrived FROM a peer never
  push back). Pure policy in `lib/core/sync_policy.dart`, tested.
- ✅ **Trusted devices first**: "Your devices" always shows every paired
  device — online dot, last-synced, one big "Sync now" that knocks on the
  last known address directly (no waiting for discovery). Seeking NEW
  devices is its own separate corner with its own "Look again".
- ✅ **Nothing hides**: sync completions and problems surface as gentle
  toasts anywhere in the app (routine background chatter stays subtle);
  every silent failure path now says what happened, in both languages.
- ✅ **Faster discovery**: hello burst on screen open + direct unicast
  knocks at trusted devices' last addresses every beat; ghost peers fall
  off the list after 2 minutes.

### Parked (don't lose)

- The wire protocol is FROZEN until the owner's phone (2026-07-29 build)
  finishes its data migration — old app and new PC side interoperate.
- Key rotation / re-pair without un-pair (today: forget + fresh code).
- Sync history line ("last 3 syncs") on the device card.

### Live test questions

- "Pair the phone to the PC: did the phone ask for the code the moment
  the PC showed it?"
- "Type a WRONG code on purpose: did both sides say so and recover?"
- "Change a routine on one device: did the other have it within ~10s
  without touching anything?"
- "Leave the Sync screen, come back: does everything still appear?"

## Wave: owl time (2026-08-10, owner: "my day isn't done in 00:00... I
## cannot set pills at 2:00 and be normal like everyone")

### The idea

Not a 36/48-hour day (that breaks every calendar date) — a MOVABLE
BORDER. The person says when their day ends (Sync screen → "When does
your day end?", 00:00–06:00). Everything before the border still belongs
to tonight. `lib/core/owl_time.dart` (pure, tested): logicalDateOf,
owlMinutesOf, actualMomentOf.

### Shipped

- ✅ **Setting** `dayRolloverHour` (0 = midnight, the old world; clamped
  0..6; rides the .bns).
- ✅ **Today's list**: 02:00 pills sort at the END of today, after the
  23:00 things; at 01:30 the screen still shows TONIGHT's list, ticks
  land on tonight's date, "what's next" knows the pills are nearest.
- ✅ **Adding a plan at 01:30** puts it on tonight's date, not tomorrow's.
- ✅ **Reminders**: "Tuesday night pills at 02:00" fire calendar
  Wednesday 02:00 (which IS Tuesday night); a plan's small-hour time
  reminds on its night; the border is part of the reminder fingerprint.
- ✅ **Windows in-app reminders, Android widget, caregiver view** all
  follow the same border — the helper sees the person's day, not the
  calendar's.

### Parked (don't lose)

- The Today header could whisper "still Saturday night" near the border
  hours — copy idea, not wired.
- Day-thread / diary views still cut at calendar midnight (reading
  history is calendar-honest on purpose; revisit if it feels wrong).

### Live test questions

- "Set the border to 04:00 and look at Today at 01:30 — is it still
  tonight's list, with the pills at the end?"
- "Tick the 02:00 pills at 02:05 — do they stay ticked on TONIGHT's
  list (and tomorrow starts clean)?"
- "Does the 02:00 reminder arrive on the right night, not at dawn of
  the wrong day?"
