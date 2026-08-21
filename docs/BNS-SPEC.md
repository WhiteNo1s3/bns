# BNS — The Specification

**Version 0.18a (machine 0.18.0+12) · 21 August 2026 · as built**

*Gentle, private, routine-and-memory support for people with neurological challenges — memory loss, executive dysfunction, traumatic brain injury, rehabilitation, dementia.*

whiteno1se enterprise (SHALTIEL) · private repository · premium, paid-only · no ads, no accounts, no cloud

---

## 0. How to read this document

This is the specification of BNS **as it exists in the tree today**, written from the laws in `AGENTS.md`, the design documents in `docs/`, and the code in `lib/`. Three words carry weight throughout:

- **Law** — an owner decision, quoted with its date. Laws are not restyled by later builds; they are obeyed or deliberately reversed by the owner.
- **Built** — in the app, shipped in a wave, covered by tests.
- **Designed / frozen / required** — written down, not in the build. Every such item is marked as such in §16.

Where the app speaks, it speaks Hebrew first (RTL) with English as the second language; this document quotes the Hebrew doors by their real names so a reader can find them on a screen.

---

## 1. What BNS is

BNS is a daily companion for a person whose memory or executive function cannot be relied on: it holds the day's routines and plans, asks one question at a time, keeps every word and every voice the person gives it, wakes them with a reason, and — when the person chooses — lets the people who care see exactly as much as the person allows, over the home Wi-Fi only.

One codebase (Flutter/Dart) ships to **Android, macOS, Windows, Linux and iOS**. The whole state of a person lives in an open folder on their own device and travels, when it travels, as one sealed file: **`.bns`**.

**Who it is for**, by the owner's own words: himself (a Level-1 daily user with a 15:00→05:00 day), his father ("dad, write things that annoy you — this is the list, we build it together"), people in rehabilitation "with their name and number on their back", and a household where "when it kills the brain only routines work."

**What it is not**: not a productivity app, not a scoreboard, not a service. There is no server, no account, no analytics, no AI API, and no word the app shows that was written for the developer instead of the person.

---

## 2. The laws

The non-negotiables, each an owner decision:

1. **THE PERSON ANSWERS — someone else may carry the bag** (2026-08-15/16). Done, skip, step progress and take-backs are born only on the person's own device. A caregiver device cannot write an answer at all; the store refuses it. Answering is available at every care level, including 4 — only *building* the list is ever locked to the helper. The voice is always *we* («לקחנו את זה?»), progress reads as readiness, an answer can always be taken back.
2. **Adult temperature** (2026-08-16). Short, warm, level, matter-of-fact. «נשמר.» beats a hug. «לא קרה — נרשם» beats «זה בסדר גמור». Never console someone who did not ask.
3. **A button wears its name.** Labeled doors, never unlabeled glyph rows; touch targets **48 dp minimum**, everywhere.
4. **The app is static** (2026-07-06). No transitions, no sliding content, no morphing themes — vestibular safety after TBI. Stationary feedback is allowed; motion of content is not. Confetti is an opt-out celebration that dies in quiet mode.
5. **Privacy absolute.** Zero network calls except explicit LAN traffic between the person's own paired devices. **No servers, no accounts — ever.** The 0.12a "account server" pivot was cancelled the day it appeared and its code is quarantined in `prototypes/cloud-pivot/`, absent from every build.
6. **Sharing is always the person's side of the wall** (2026-07-06). A care level widens what *leaves* toward the people who care; it never filters what the person sees.
7. **THE EAR IS OURS, AND IT DOES NOT EDIT THE PERSON** (2026-08-19). Speech becomes words through whisper.cpp compiled into the app; borrowed engines are fallbacks asked with masking off. Nothing between the mouth and the box may filter, star out, soften or "fix" a word — "curses must be inside the speech, no censor".
8. **Words come off a kept take, never off a live session** (2026-08-19). Press to record, press to read; nothing a finger does can cancel a recording. Takes queue; the mic is never dead.
9. **Every take is kept.** A recording the person made is never orphaned.
10. **Silk memories** (2026-08-14). If the person recorded it, they see it; `quick/remember/memorize` is retention, never a hide filter.
11. **"I am mad" mode is sacred.** Rage gets first-class, judgment-free space; vents burn out within ~2 days; never quoted back, never in summaries or shares.
12. **No punishment language**, no streaks that hurt, no red X. A deliberate skip is a decision, and deciding counts.
13. **Every visible word is for the person, never the developer** (2026-07-08).
14. **One map** (2026-08-16). The bar holds the main rooms, the menu holds the rest; Today carries no second copy of either.
15. **The day appears once, and stays steady** (2026-08-14/19). Answering never moves a tile; the day is not painted three times.
16. **STT everywhere.** Every field a person writes in wears the mic.
17. **Receive first, then send** (2026-08-16). A helper's device pulls the person's truth, merges, and only then pushes the built day — never a blind push into a phone.
18. **Ship builds, not source; Android is the flagship** (2026-07-06). Premium, paid-only, ~$1–2, no ads, no free tier, no subscriptions.

---

## 3. Platforms, versions, distribution

| Platform | State | Notes |
|---|---|---|
| **Android** | Flagship. Lived daily on a Galaxy S23 (SM-S918B), Android 14+ | release APK, R8 + obfuscated; home-widget bundle; `.bns` association; alarm channel; whisper_ggml native |
| **macOS** | Native, lived daily on Apple Silicon; the test harness runs here | sandboxed, LAN entitlements, `.bns` document type; ad-hoc signature |
| **Windows** | Built and lived (the first platform) | portable zip, in-app reminder card (no system notifications for Flutter) |
| **Linux** | Built (Kubuntu laptop) | desktop parity |
| **iOS / iPadOS** | Build-ready (runner, entitlements, document types, icon) | not yet lived on a device; needs a paid Apple identity for distribution |

**Versioning — the alpha law** (2026-08-18): human version `0.XXa` lives in one place (`lib/core/version.dart`, `kBnsVersion`) and climbs **+0.01 per shipped wave**; machine version `0.XX.PATCH+N` in `pubspec.yaml` — PATCH for fix-only builds, `+N` the Android versionCode that climbs on every shipped build and never resets. `test/version_law_test.dart` welds the two. The `a` falls only at **1.0 — the build where the Level-1 day runs clean end to end and distribution signing is done**. Current: **0.18a / 0.18.0+12**.

**Signing**: the Android release keystore lives on the build Mac; Apple builds are ad-hoc signed (runnable on the owner's machines, not shippable through a store yet).

**Deploy loop**: `scripts/deploy-all.sh` builds macOS + Android release, names `dist/` files by the human version, installs on the connected phone (`adb install -r`, data kept), replaces `/Applications/bns.app`, and re-dresses the six harness apps. Proof of a deploy is never "adb Success" but `dumpsys package … versionName/versionCode` on the device, and the menu footer version line for the person.

---

## 4. The person's day

### 4.1 Owl time — the border of the day is chosen

Law (2026-08-10): "my day isn't done in 00:00… I cannot set pills at 2:00 and be normal like everyone." Two settings define a person's 24-hour day entity:

- `dayRolloverHour` (0–6) — when the day **ends**. With border 05:00, pills at 02:00 sit at the end of tonight's list, after the 23:00 things; the list flips while the person sleeps, never in their face.
- `dayStartHour` (0–23) — when the day **begins** (the owner: 15:00 → 05:00). Set on Today by the door «מתי היום שלך מתחיל?»; once an hour is chosen the same door reads it back (for the owner: «היום מתחיל 15:00»). The value 0 means unset or midnight, and it is never written without a tap.

Every "today" in the app goes through these two (`lib/core/owl_time.dart`: logical day key, person-day start, owl minutes, actual moments). Future days are look-only ("nobody can do tomorrow today"); a day that passed takes no new plans.

### 4.2 Today (levels 1–2) — the quiet day

Rebuilt 2026-08-19 after the owner's "all I wanted is to check what left in my day": the day appears **once**.

- Nothing above the work: no pep talk; the mad banner only while mad mode is on; the vent chip «אני כועס/ת» stands alone, small.
- Questions that need answering may interrupt, once: the unset day-start door, and — since 0.18a, see §4.6 — the wake door «היום מתחיל ב-15:00 — קמת?».
- **The hero — «הבא»**: the one spotlight, chosen by the person-day rank (morning things are *the next morning* once evening has begun; night slots before the border are still tonight). Doors: «בוצע», «משהו הפריע» (the miss sheet), «שינוי שעה» (a one-time move), and «חלק 2 מתוך 3» while mid-steps.
- **The list — «הרשימה של היום» with «N נשארו»** always on. One line per thing (`DayQuietRow`): clock, name, state. Tap = quiet ✓ (no second question). Pencil = the one miss door. Long-press = «שינוי שעה». Backpack only when the plan carries a bag. Answered rows dim in place. Order: morning→night, or "what's next" by choice.
- Doors under the list: «תוכנית להיום» (a one-time plan, the ONE add ask), «לסדר את מחר, כשרגוע» (the Tomorrow room).
- Then: hard moments kept today (when any), **What you kept** strip (the proof a recording went somewhere), the **Diary** box («איך היום מרגיש?», mic in the field, «לשמור ביומן»).
- **The quiet footer** — machinery under the day, never above it: the set day-start door, the wake line («קמת ב-17:45 — הרשימה זזה לשם. רק להיום.»), the last-sync line.
- No floating action button at levels 1–2. Guided (level 4) keeps its own tuned flow: only the list, big tiles, the telling bar.

### 4.3 Routines

A **routine** (`Routine`) is a recurring thing in the person's day: title, optional description, recurrence (`daily` / `weekdays` / `weekly` / `custom` with days of week), an optional clock on a quarter hour, **steps** (ordered parts, each with a note; "first step only" mode), tags (`family`, `need-help`, marks), `isActive`, and **`timeByDay`** — per-day clock overrides keyed by the logical day, so a 16:00 water moved to 17:30 today is 16:00 again tomorrow.

The routines editor («השגרות שלי»: add, change, remove) carries the mic on every field — title, description, each step's title and note.

### 4.4 Plans

A **plan** (`CalendarEvent`, never called a "task") is a one-time thing: date, optional time (quarter hours), notes, all-day flag, **`shareWithFamily`**, `needHelp`, an **answer** (`done` / `skipped`, with `answerReason` and `answerAt`), and a **gather list** — «מה לוקחים?», a question the person answers item by item ("2 of 4 are with us").

Law (2026-08-09): **a plan carries weight** — it stands in Today like a gentle step and can be answered. Plans are added through one ask everywhere (Today's «תוכנית להיום», the day view, the calendar's +): the name field starts empty with a mic, «הוספה» sleeps until a name exists, ביטול creates nothing — the app never invents a plan.

### 4.5 Answering

- **Quiet ✓** — tap the row or the hero's «בוצע». No follow-up question.
- **The miss sheet** («משהו הפריע» / the pencil): title, one kind line ("deciding counts"), a text field with a mic, «זה לא קרה היום» (always skips), «סגירה» (with words skips, empty just closes; tap-out with words skips too). A spoken why is **settled** before the sheet answers — a confirm can never outrun the ear or delete a recording mid-take. A wordless skip is the person's right and reads honestly afterwards: «לא קרה — לא נשמרה סיבה».
- **Steps** advance on the hero; kept words live in «מילות היום»; reasons live one door away in the day view.
- **Take-back** — an answer can always be undone.
- On a **caregiver device** state is a fact (a ✓ or an open dot), never a control.

### 4.6 Moving the day

- **«שינוי שעה»** (one-time move): the fusion sheet — an hour rail, the time big in the middle, one confirm wearing the hour — floored at now for today, writes `timeByDay` for this day only («רק להיום — השגרה הקבועה לא משתנה»). The list follows in the same breath; reminders reschedule.
- **The day starts when you wake** (0.18a, 2026-08-21): the routine is a **shape** whose head is the first routine of the person-day in owl order. «קמתי» slides the head to the real wake and every routine of today follows by its own gap — today only, through `timeByDay`, so the list, הבא, reminders, day view, widget and the Care seat follow. Plans stay on the clock; answered rows stay; a row the person already moved today keeps their move; quarter hours; nothing crosses the border. One anchor per day (`settings.wokeAt`) from three doors: the ring popup's «קמתי ✓», the notification's «קמתי ✓», and the Today door «היום מתחיל ב-15:00 — קמת? / קמתי / עוד לא קמתי» (the latter hushes until the next open).

### 4.7 Tomorrow, set up tonight

Law (2026-08-15): "I woke up today at 15:30… I had no clue what to do." The Tomorrow room («לסדר את מחר») builds the coming day while it is calm: plans for tomorrow, the gather list («מה לוקחים?»), ideas that wait for their day («להוסיף רעיון ליום הזה» — a capture with `forDate`, shown on that day). Tomorrow itself is look-only until it comes.

### 4.8 Calendar and the day view

«לוח שנה» shows the days that are actually there — 20 days of kept history, 10 days ahead, no scrolling into years nobody can touch. A day view lists plans, the day's routines with their state and kept whys (readable aloud), the day's memories/ideas; past days are read-only; future days are looked at.

---

## 5. Memory and words

### 5.1 The capture room — «הקלטה ותיעוד»

Nothing above the mic. **One mic** (`VoiceTake`): press to record, press to stop; the voice is safe the moment recording stops; the words are read off that same take (`Ear`) and appear in the box («המילים מופיעות כאן. אפשר לערוך, או לכתוב עוד.»). Several takes in one visit all land in one note and all voices are kept (`extraAudioPaths`). «להקריא את המילים» reads them aloud. A folded door «תגיות ושיתוף» holds: keep this one always, family can know, a mark on the moment («סימן»), context. **One pinned Save** rides above the keyboard; «חזרה ליום שלי» guards unsaved words. A new visit banks leftovers as a kept thought and opens clean. The widget's 🎤 opens the room already recording.

### 5.2 Memory levels, retention, trash

`quick` / `remember` / `memorize` is **retention**, never visibility (the silk law). Rolling retention **20 days** of history (configurable; long horizons allowed, slower syncs), calendar +10 forward. Trash holds a removed memory **3 days**, then it is gone. `memorize` keeps forever. The person can remove anything, with a confirm.

### 5.3 Memories, the day thread, the diary

- **«זיכרונות»** — everything kept: search («למצוא זיכרון…», with a mic), the marks row filters by one mark, voices play in place, trash.
- **«מילות היום» / `/day`** — everything said and done on a day: done, didn't-happen + reason, hard notes, diary lines, thoughts, plans; search (with a mic); a care glance under full care (soft help signals, never a scoreboard).
- **The diary** box on Today — «דבר טוב, דבר קשה — לשניהם יש מקום כאן.» One line, kept as a diary memory.

### 5.4 "I am mad" — the rage valve

«אני כועס/ת» turns the mode on for ~24 hours; the capture room becomes a vent («להוציא הכול. רק אתם רואים את זה. זה נמחק מעצמו.»); vents (`mad-vent`) burn out within ~2 days regardless of retention; they are never quoted back, never in summaries, never in a filtered share — they reach a **helper only at level 3–4**, because "annoyed at the elevator" is how you know to help with elevators. A cooled-storm share door is designed, awaiting the owner's yes.

### 5.5 Marks — «סימן»

A person's own vocabulary of marks (not "tags"): chosen in capture, suggested from the words as they land (one tap accepts, nothing applies itself), filtered in Memories.

### 5.6 Need help

The person can open a **Need-help ask** on a routine or plan; at level 1 that opened ask is the only thing that ever travels («ביקשתי עזרה בזה»). A skip, a late tick, a mood or silence is never an ask; a skip-derived need-help note must never look like one.

---

## 6. Voice — the ear and the mouth

**The ear ladder** (`lib/services/ear.dart`), one for the whole app, every platform:

1. **`WhisperEar`** — whisper.cpp compiled into the app (`whisper_ggml`), model **small** (~490 MB, the first rung where Hebrew is genuinely usable), downloaded once from the settings door «אוזן משלנו — עובדת בלי רשת», then offline forever; identical words on Android, iOS, macOS, Windows, Linux. `noContext` per take (no self-feeding loops); the ffmpeg conversion crumb is swept.
2. The platform's own file ear — Google's segmented-session file recognizer on Android 13+ (16 kHz, paced, masking off), Apple's on-device recognizer on iOS/macOS.
3. The old desktop doors — downloaded whisper-cli (Windows), Vosk (English).

Every rung answers `''` rather than throwing; `sttEnabled` off is silence from every rung; a device with no ear hides the mic rather than lie. **Takes queue** — speaking twice in a row never freezes the mic («עוד כותבים את המילים הקודמות — רגע אחד.»). **`DictationMicButton`** sits on every person-written field (capture words and context, diary, the miss sheet, the gather sheet, marks, plan names, routine editor fields, search boxes, names in settings); each keeper **settles** the mic before it saves. Passwords, the pairing code and typed-confirmation gates stay typed on purpose.

**The mouth**: TTS in the app's language (he-IL / en-US; Carmit on the owner's Android) reads words aloud on request and speaks the widget's subject prompt before the mic opens — never into the recording. Nothing speaks or listens unless its worded button is pressed.

---

## 7. Wake and reminders

### 7.1 Reminders that actually arrive (2026-08-08)

A gentle reminder for every routine with a time, on its days; a heads-up before timed plans (`eventReminderMinutes`: off / on time / 10 / 30 / 60). The person chooses how loud — **quiet / gentle / bright** (three Android channels, one clean entry in system settings) — and the color (the palette, or a gentle named color; never red). Shade actions answer right there: **done**, **why** (opens the miss sheet), **later** (2 hours, "by my will"). Reminders survive restarts, reschedule after any edit/sync/import, honor `timeByDay` and the wake anchor, and **stay silent on a caregiver's device**. Windows shows an in-app card. Planning is pure and tested (`lib/core/reminder_plan.dart`).

### 7.2 The wake — «השכמה» and «שעון מעורר»

Law (2026-08-18): "many days have nothing to wake up for and I do have." A daily wake (`wakeAlarmTime`, optional `wakeAlarmNote`) rings as a **real alarm** (alarm channel, exact, Doze-immune, full-screen) and carries **the reason** — the day's first three things in owl order (02:00 night pills never lead the morning); an empty day still says «היום שלך מחכה לך.»

- **The ring popup** (`/awake`): silences the loop the moment it is seen; one screen — big clock, the reason, **«קמתי ✓»** (the day opens, and anchors at this hour — §4.6) and **«עוד 10 דקות»** (one return ring, survives reschedules). Back answers like קמתי. Both answers also ride the notification itself.
- **Plant it in the phone's clock** («לשתול גם בשעון של הטלפון»): one tap opens the phone's own alarm app pre-filled — the person picks their song there; the phone-clock alarm survives force-stop, BNS's ring carries the meaning.
- **The alarm page** («שעון מעורר»): the wake on top; «מה נשאר היום» — the unanswered missions in person-day order; tap a mission → once / every day / certain days → the phone's clock opens pre-filled («a breach to OS, to make things tick»); plus «צלצול חופשי».
- Level 1–2 self-serve; guided and Care seats see their own version (§9).

### 7.3 The Care alarm — «צלצול לכולם»

A helper sets one time + words for everyone they sit for; it writes a copy into every profile and rides the loop onto each person's clock by **hand-delivery** (push-only, so the receive-first leg cannot eat the instruction). Adoption: levels 3–4 always; levels 1–2 only onto an empty nightstand (they own a wake they set); a helper's empty never wipes. The helper's pocket stays quiet.

---

## 8. The care levels

The level is one visible choice (the "Care level" card in Settings & sync); two flags are the source of truth — `fullCareMode` (3) and `guidedMode` (4, implies 3) — kept coherent with the card in both directions.

| | **1 — Independent «עצמאי»** | **2 — Family knows «המשפחה בעניינים»** | **3 — Full care «ליווי מלא»** | **4 — Guided «מונחה»** |
|---|---|---|---|---|
| Who | the default; someone managing their own memory | independent, family should know the important things | the last resort, decided together | when routines are what remains |
| What leaves | nothing — except an opened **Need-help ask** | only what was chosen: plans «המשפחה יכולה לדעת», routines tagged `family`/`need-help` (with their ✓/skip), moments tagged `family` (voices ride along), asks — never a mad-vent | **everything**, rants included — to the helper only | everything (4 implies 3) |
| The person can | everything | everything | everything — the window opens wide, nothing leaves their hands | **only the list**, big: tick with the gentle "is it done?", long-press to tell a problem; cannot add/edit/delete or build |
| The helper | sees an ask, may add/refresh upcoming facts | read-only family view; may refresh a shared upcoming thing or add a shared routine | **monitors, never edits**; builds and watches the day; answers arrive only by sync | the inspector builds and edits everything; changes arrive by LAN auto-sync |
| Doors | free | free | ON guarded (typed share name, the caregiver's key chosen together); OFF opens with **the key** | same key; the caregiver door on Today opens with the key |

Shared machinery: `careLevel` + the two flags + `careLockHash` (salted hash only — the password itself never exists on disk; a pre-lock device still lowers freely; leaving to 1–2 retires the key); the share mapping in `lib/core/need_help.dart` is the single law for what a window may receive (1 asks-only, 2 chosen family, 3–4 full); **hats never travel** — a caregiver device keeps its own role, level, share name and key on merge and restore, and a person's device never adopts a helper's flags (guided containment, `test/care_containment_test.dart`). `caregiverDevice` is a role, not a level. "Level 5 — the sketchbook" (a caregiver-only profile with no pairing) is design only.

---

## 9. The Care seat

A caregiver device (a role) is the helper's copy: it builds the other person's day, never nags its holder, cannot write answers. Its home screen shows: the people dropdown **«אנשים»** (profiles — one seat, many people; wave 1: registry, migration, sitting, inbox; the **switcher** that lets one seat follow several people live is REQUIRED and not shipped); the connection line («מחוברים ל־רמה 2 — נשמע לאחרונה לפני 0 דקות»); **«צלצול לכולם»**; **«השעון שלהם»** — the person's day window (היום מתחיל 15:00 · נגמר 05:00), set from the seat by hand-delivery; **«התוכנית למחר»**; the **inspector** — the person's day as facts («7 ברשימה היום»), «כדאי לדעת» soft notes (hard moments this week, things that returned), the list with «שינוי שעה» per row; a calendar where state is a fact, never a checkbox; «השכמה גרה אצלם» where the wake lives. The directional law governs every sync from this seat: **receive first, then send**.

**BNS Care as its own entry point** (one repo, a second `main`, per-profile live serving) is designed, not built.

---

## 10. Sync and security

**The promise**: only `.bns` files ever travel the LAN, and only between devices you paired. No third party in the middle, ever.

- **Discovery**: UDP broadcast on **42424** with the `BNS_HELLO` magic (non-BNS packets fast-rejected); when UDP cannot bind (same-Mac siblings), a TCP **`WHO`** knock on **42425–42432** (loopback + this machine's IPv4s) finds the sibling — header-only identity (id, bound port, name), no pair, no data; each knock reads one line or 600 ms and always closes.
- **Transfer**: TCP from **42425** (each instance owns its own port); header-framed `PUSH` / `PULL` between known device ids.
- **Pairing (first sync with an unknown device)**: encryption required; a **6-digit code** shown on both screens; the asking device presents its **share name** (a chosen, family-facing name, never the phone's technical name); explicit "codes match" + accept; only then the encrypted transfer. The device becomes **trusted**.
- **Trusted devices**: per device — name, last address/port, last sync, shared secret (stays on-device, never exported into `.bns`), **auto-sync** toggle, **LAN allowed** kill switch (keeps the pairing, stops transfers both ways), `peerIsHelper`. Forget at any time.
- **Crypto**: every payload **AES-CBC** with a fresh random IV per transfer, per trusted device; `PULL` only gets data encrypted with the requester's key; big payloads encrypt on isolates. Unknown devices get nothing — not even plaintext metadata.
- **Validation**: every received payload is structurally validated (ZIP magic, `mimetype` marker, manifest, data) and its **SHA-256 seals** verified before anything reaches the store; a hostile, truncated or wrong-key file is rejected whole. The same validation guards manual imports.
- **The care window**: what a helper's device may receive is the per-level wall (§8) — a filtered **export**, never a filtered view; own devices always get the full day. `pushTrustedNow` / **hand-delivery** (`pushOnly`) sends an instruction without the pull leg eating it; every adopt rule still runs on the receiving side.
- **Merge** (`lib/core/care_sync_merge.dart`): plan fields and answers merge separately (a ✓ never hides Saturday, a Care edit never eats the ✓); `timeByDay` unions; newer write wins on plan fields at level 3; level 4 takes Care's plan and keeps the person's answers; Care-empty never wipes a person; hats never travel.
- **Progress always visible**: a stream reports every step (export, encrypt, transfer, import) into a modern progress bar in the system or palette color, with level words.
- **Manual fallback**: export / import `.bns` by hand (USB, AirDrop, mail to self).
- **Status**: the sync wave is **frozen** until the Level-1 day runs clean; the per-level window's asks-only width and ask-notify are designed with no callers yet (today LAN sync to a trusted device carries the full store at every level — stated honestly in `docs/bns-format.md`).

---

## 11. Data and the `.bns` format

**The live database is an open folder — the wardrobe stays open, the suitcase is packed at the border** (2026-07-05): `bns_data.json` + `audio/` + `exports/` in the **BNS home**, every change written immediately and atomically (temp + rename; a crash loses at most the keystroke in flight). The home is a chosen folder named by a pointer file `bns_home.txt`; a dressed harness app finds its sibling `person/` or `caregiver/` store by structure.

**`.bns` = the travel form**: a standard ZIP (`application/x-bns`), **zip-v2**, the only writer:

```
BNS_Backup_2026-07-05_1430.bns
├── mimetype        # FIRST, STORED: "application/x-bns" → bytes 30..54 of the file
├── manifest.json   # formatVersion 2, deviceId/deviceName, appVersion (0.XXa), schema bns/v2,
│                   # packer "zip-v2", integrity { sha256 of data.json.gz, sha256 per audio }
├── data.json.gz    # routines · events · captures · completionLogs · settings
└── audio/          # cap_<short-uuid>.m4a / .wav (STORED), streamed, sealed
```

Verify-after-write, keep the previous good as `.prev`, rename only after verify; unpack verifies ZIP CRCs **and** the seals before anything reaches the store; a single flipped bit is rejected with a friendly message. Streaming both ways keeps memory flat for hours of recordings. **Silent lifecycle imaging**: on background/close the app refreshes one stable `exports/BNS_Latest_<device>.bns` — a current shareable file always exists. Two official implementations (Dart in the app; JavaScript in the satellite), cross-verified by `tool/cross_check.dart`. Readers also accept BNS2 / BNS3 / BNS Wire (research containers) and legacy v1 files.

**The models** (all ids UUID strings, dates `yyyy-MM-dd` local, clocks `HH:mm`):

| Model | Fields (the meaningful ones) |
|---|---|
| `Routine` | title, description, recurrenceType, daysOfWeek, time, **timeByDay**, isActive, tags, firstStepOnlyDefault, steps[title, note], createdAt/updatedAt |
| `CalendarEvent` (plan) | title, date, time, notes, isAllDay, **shareWithFamily**, needHelp, answer/answerReason/answerAt, gather[text, takenAt], createdAt |
| `QuickCapture` (memory) | at, text, transcript, audioPath, extraAudioPaths, contextNote, linkedRoutineId/EventId, tags, memoryLevel (quick/remember/memorize), isDayMemory, forDate, deletedAt |
| `CompletionLog` | routineId, date, status (done/skipped), reason, reasonAudioPath, at |
| `TrustedDevice` | id, name, lastAddress/lastPort, lastSyncedAt, sharedSecret (device-only), autoSyncEnabled, lanSyncAllowed, peerIsHelper |
| `AppSettings` | see §12 |

**Import / merge rules**: last-updated wins per collection; audio copied in (collisions by hash or suffix); a summary shown and confirmed; "use this backup exactly" also offered. **Family file** `BNS_Family_*.bns` = the chosen window only.

**Retention**: 20 days of history, +10 ahead, trash 3 days, mad-vents ~2 days. **Associations**: `.bns` opens BNS on Android (VIEW intent), macOS/iOS (document types, `com.whiteno1se.bns`), Windows/Linux (registration at packaging).

**The web satellite** (`satellite/bns-web.html`): one static HTML file that opens, shows, edits and re-seals `.bns` entirely in the browser — the window for the people *around* the person (family view for `BNS_Family_*`, `#family` read-only window). A document tool, not a service: no server, no network, no storage, no traces.

---

## 12. Settings inventory

| Group | Keys |
|---|---|
| Identity | `deviceName`, `deviceId` (stable; never travels in a care window), `shareName` |
| The day | `dayStartHour`, `dayRolloverHour`, `todayOrder` (timeline / next), **`wokeAt`** (`yyyy-MM-dd HH:mm`, one anchor per day) |
| Wake | `wakeAlarmTime` (`HH:mm`, `''` = off), `wakeAlarmNote` |
| Reminders | `notificationsEnabled`, `reminderStyle` (quiet/gentle/bright), `notificationColor`, `eventReminderMinutes`, `reminderTimeoutMinutes` |
| Care | `careLevel` (1–4), `fullCareMode`, `guidedMode`, `careLockHash`, `caregiverDevice` (role) |
| Voice | `sttEnabled`, `sttLocale`, `quietMode`, `hapticsEnabled` |
| Look | `themeMode` (system/light/dark), `relaxingPalette` (clay · lavender · sand · rose, or the OS dynamic color), `appLanguage` (he/en), `userType` (normal / kid-ADHD / ADHD / penguin — scale and tone) |
| Data | `retentionDays` (20), `widgetForwardDays` (2), `autoImageEnabled`, `lastFullSyncAt` |
| Mad | `madModeUntil` |
| PC | `keybinds`, `enabledKeybinds` |
| Retired | `serverUrl`, `serverToken` (the cancelled pivot; unused) |

Pre-`careLevel` stores migrate on read; unknown values fall back safely so newer files never break older apps.

---

## 13. Accessibility, copy and the map

- **Hebrew first, RTL**, English second; the whole tree re-skins live. Copy laws: adult temperature; the app's own voice in **infinitives and plural doing-forms**, never masculine imperatives; **one word for the helper — «מלווה»**; no builder talk; honest doors (a state line says what is true; a door says what it does); no slogans.
- **The map — one map**: the phone bar holds **היום · הקלטה · זיכרונות · לוח שנה** (a Care seat sees «שגרות» instead of «הקלטה»); the menu ☰ holds **מילות היום · שעון מעורר · השגרות שלי · הגדרות וסנכרון**; the footer of the menu wears the human version. Off-map rooms (settings, menu) show no lying indicator. Guided mode has no bar and no menu — the list is the door, and wandering off surfaces a way home.
- **Desktop**: a sidebar rail (Today, routines, day diary, calendar, memories, capture, sync), a menu bar, a comfortable reading column, the date in the top bar, keyboard navigation of the day (Ctrl+G jumps to the list, ↑↓ move, Enter = done, S = skip with reason), shortcuts (Ctrl+T Today, Ctrl+N capture, Ctrl+R routines, Ctrl+Y day diary, Ctrl+M memories, Ctrl+, settings, Ctrl+D diary focus) — **keybinds are live, editable in Settings, and travel in `.bns`**.
- **Bigger words, bigger targets**: 48 dp floor everywhere; phone-first sizes for the doors; text scale by user type.
- **Themes**: OS dynamic color first, else the relaxing palettes; light/dark/system; no red for reminders.
- **Quiet mode**: no confetti, no extra stimulation. **Haptics** optional.
- **Every screen has an escape** — no dead ends (back goes home, never a trap; held by `test/no_dead_end_test.dart`).

---

## 14. Android extras

- **The widget bundle** (hand-written Kotlin, `home_widget`): **Today** — today's mission + gentle progress; **Coming up** — plans for the next N days (default 2, "nobody needs more stress than 2 days") + one recent memory; **Quick actions** — + Task, + Memory, **🎤 Voice** (opens the app already recording). Updates on every data change.
- **Alarms**: the wake and mission alarms use the alarm channel (exact, Doze-immune, full-screen); mission alarms can be planted into the phone's own clock with repeat days (`EXTRA_DAYS`).
- **Permissions asked kindly**: notifications (Android 13+) never block the first frame ("the first frame is sacred"); microphone; local network (macOS/iOS prompt with person-facing words).
- **Build notes**: release is R8 + obfuscated; `whisper_ggml` needs its library module raised to the ffmpeg it carries (done in `android/build.gradle.kts`); NDK 29 is advised by the plugin.

---

## 15. Quality — how BNS is proven

- **Tests**: 57 test files, **378 tests** at 0.18a — pure laws (owl time, day weaving and next-rank, reminder plan, wake anchor, care merge, containment, packers and tamper checks, version law) and widget tests (the doors, sheets, rows). `flutter analyze` clean (style infos only).
- **Lived testing — the harness**: dressed copies of the app with their own bundle ids, entitlements and **real stores**, living inside the repo as `.l2-test/` (BNS-L2 + BNS-Care), `.l3-test/` and `.l4-test/` (BNS-Person + BNS-Care each), all gitignored, all re-dressed by every deploy, launched by their `LAUNCH.sh` (kills stale processes, seats the pair side by side). Personas (L1 on the real S23, L2/L3/L4 pairs on the Mac, a Caregiver, a Prototyper, "Eagered") live the build and report in their own words.
- **The standing loop**: a report is a bug **and** a design law → TRIAGE (`docs/user-reports/TRIAGE.md`) holds the queue → build → tests green → `deploy-all.sh` → proof by `dumpsys` on the device and the footer version line → the pass is recorded in `docs/changes.md`. Evidence screenshots live in `hunt-shots/`.
- **The 1.0 bar**: the Level-1 day runs clean end to end and distribution signing is done.

---

## 16. Status, roadmap, and what is deliberately not built

**Shipped waves (the recent arc)**: 0.11 owl time + plans + silky sync · 0.12a the alpha law, the void closed · 0.13a the wake gets its own door · 0.14a the alarm page · 0.15a the ring you can answer, the Care alarm over LAN · 0.16a Today quiet, the file ear, «שינוי שעה», the gendered-imperative sweep · 0.17a the ear inside (whisper in-app, one mic), the skip-why that waits for the mouth, named plans, STT on every field, the take queue · **0.18a the day starts when you wake**.

**Required, not shipped** (owner's word, in the ledger):
- **One Care, few people** — the profile switcher that lets one seat follow several people live (wave 2 of profiles). Frozen with the sync wave until the Level-1 day is clean.
- **BNS Care** as its own entry point (`main_care.dart`), per-profile live serving, the ward view.

**Designed, awaiting the owner's yes**: level 5 (the sketchbook), the cooled-storm share door.

**Not built on purpose** (each a decision): a time picker for "I actually woke earlier" (the ring's קמתי anchors at the alarm; «שינוי שעה» fixes any row); "exit the app" on «עוד לא קמתי»; any cloud, account, analytics, AI API, free tier or ad; any word filter in the ear.

**The Level-1 queue now**: the four-door miss-sheet count, the hero wrong-goal confirm, the full-app Hebrew copy audit (seat charter: `COPY-AUDITOR.md`), and living 0.18a's wake door on the S23.

---

## Appendix A — Rooms and routes

| Route | Room | Who sees it |
|---|---|---|
| `/` | Today («היום») — or the Care home on a caregiver device | all |
| `/capture` | «הקלטה ותיעוד» — the capture room | all (guided: the telling bar) |
| `/memories` | «זיכרונות» | all but guided |
| `/calendar` | «לוח שנה» + day view | all |
| `/day` | «מילות היום» — the day thread | all but guided |
| `/routines` | «השגרות שלי» | levels 1–3 (building), Care seat |
| `/tomorrow` | «לסדר את מחר» | levels 1–3 |
| `/wake` | «השכמה» — the wake room | person; Care seat says where the wake lives |
| `/awake` | the ring popup (no shell, two doors) | the ringing device |
| `/sync` | «הגדרות וסנכרון» — devices, reminders, backup, care level, voice, keybinds | all but guided |
| `/menu` | ☰ — the rest of the map + the version footer | all but guided |

## Appendix B — Glossary (Hebrew doors)

«היום» Today · «הבא» the next thing (the hero) · «בוצע» done · «משהו הפריע» something got in the way (the miss sheet) · «שינוי שעה» a one-time move · «הרשימה של היום» today's list · «N נשארו» N left · «תוכנית להיום» a plan for today · «לסדר את מחר» set up tomorrow · «מה לוקחים?» what do we take (the gather list) · «מתי היום שלך מתחיל?» / «היום מתחיל 15:00» the day-start door · «קמתי» / «עוד לא קמתי» I'm up / not up yet · «השכמה» the wake · «שעון מעורר» the alarm page · «צלצול לכולם» the Care alarm · «השעון שלהם» their clock · «הקלטה ותיעוד» recording & notes · «זיכרונות» memories · «מילות היום» today's words · «סימן» a mark · «אני כועס/ת» I'm mad · «מלווה» the helper · «המשפחה יכולה לדעת» family can know · «אנשים» people (profiles) · «אוזן משלנו» our own ear (the offline whisper).

## Appendix C — Where things live

`lib/core/` pure laws (owl_time, day_items, day_feed, reminder_plan, wake_words, wake_anchor, care_sync_merge, need_help, kept_memory, keybinds, models) · `lib/features/` the rooms (calendar, capture, caregiver, diary, memory, routines, sync, wake) · `lib/services/` ear, voice_take, whisper_ear, android/apple file ears, vosk, tts, notifications, wake_anchor_service, file_handler · `lib/data/` the store (`local/isar_service.dart` — historical name, a JSON snapshot store), `pack/` (zip-v2 and the other packers), `sync/lan_sync_service.dart`, `export/` · `lib/ui/` theme, the shell, the widgets (doors, sheets, rows) · `lib/platform/android_widget.dart` · `satellite/bns-web.html` · `scripts/` build + deploy · `docs/` this document and its sources · `test/` 57 files.

---

*This document is regenerated per wave. Its sources of truth: `AGENTS.md` (laws), `docs/care-levels.md`, `docs/care-profiles.md`, `docs/sync-security-and-progress.md`, `docs/bns-format.md`, `docs/versioning.md`, `docs/testing-live.md`, `docs/changes.md` (the log), `docs/user-reports/TRIAGE.md` (the queue), and the code.*
