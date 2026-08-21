# Changes — iterate notes for the next model

This repo does not carry `PROTOTYPER.md`, `GROK.md`, or `CLAUDE.md`
(those stay with the gBNS / grokBNS forks). This file is the same kind
of handoff: what just changed, what must not be undone.

## 2026-08-18 — L2 Today asked while Person disk already had 15

Lived ~19:16 IDT, isolated L2 Person on 0.14a / 04c0bf7. Look-only.

- Person `/Users/ben/dev/gBNS/.l2-test/person/bns_data.json`
  `settings.dayStartHour = 15` (rollover 5). Care sitting רמה 2 also 15.
- Today still showed «מתי היום שלך מתחיל?». Expected «היום מתחיל 15:00».
- L2 did not open הגדרות. Did not tap. Ben set 15 earlier so Care
  aligns; L2 did not tap.

Cause: the running bundle `com.whiteno1se.bns.l2person` was not reading
`.l2-test/person`. macOS `open` does not pass `--data-dir` or
`BNS_DATA_DIR` into Dart, so overlay + relaunch opened the bundle's
own documents (unset 0). Today also kept `_dayStartHour = 0` until the
rest of `_refreshDoneToday` finished — a loaded 15 could sit behind
the question.

Held:

1. Dressed `.lN-test/*.app` pins sibling `person/` (Person) or
   `caregiver/` (Care). `--data-dir` / `BNS_DATA_DIR` still win. Stock
   `/Applications/bns.app` is untouched.
2. Today setStates the clock as soon as `getSettings()` returns. Door
   already correct when passed hour != 0.
3. 0 stays unset / wiped default. No auto-write of 15. Confirm still
   writes. No הגדרות.

Do not reset L2's 15. Do not invent a Care clone.

## 2026-08-18 — One speaking: the Android file ear, and the capture room sheds its noise

Owner (Hebrew chat session): «רציתי שמהתחלה יהיה גם הקלטה וגם יצירת
טקסט מהדיבור… לגרום לגוגל להוציא מילים מההקלטה גם מגניב», plus a batch
of capture-room renames and «יש ספאם של טוסטים… אסור שיהיה מצב כזה».

- **THE FILE EAR (Android 13+).** `bns/file_stt` in MainActivity feeds
  the KEPT take into the system recognizer through
  `RecognizerIntent.EXTRA_AUDIO_SOURCE` (pipe fd, PCM16 mono; WAV parsed
  by hand, m4a via MediaCodec). One speaking → voice kept AND the same
  audio becomes words; nobody says anything twice. Dart side
  (`lib/services/android_file_stt.dart`) probes once per phone with
  `assets/audio/ear_probe_he.wav` (Carmit says «שלום, מה שלומך היום?»)
  across three doors — on-device / Google-by-name / system default —
  and remembers the winner in support/`file_ear.txt` (device truth,
  never synced; `.gitignore` got a negation so the asset itself ships).
  Probe failure = the popup flow exactly as before. **S23 verdict
  PENDING — needs one lived take**; `adb logcat | grep "file ear"`
  tells which variant answered.
- **Curses survive**: `EXTRA_MASK_OFFENSIVE_WORDS=false` on the popup
  and the ear (mad-vent law — the person's own words, all of them).
- **Renames (owner)**: the capture room is «הקלטה ותיעוד» (screen title,
  home bar, memories FAB; phone nav chip «הקלטה», desktop rail carries
  the full name). The options door is «תגיות ושיתוף» — one name open or
  closed, same tap closes. Save is «שמירה» with the ✓ alone. The exit is
  «חזרה ליום שלי» (same words as everywhere). Above the mic nothing
  remains but a mad-vent's promise; the «הקשה להקלטה נוספת — שורה חדשה»
  caption is gone.
- **The toast law** (`lib/ui/snack.dart`): `BnsSnack.show` clears before
  it shows — newest replaces, nothing queues. 79 call sites swept. The
  desktop REMINDER card was deliberately NOT swept (a reminder surface
  with actions, not tap feedback). Do not reintroduce raw
  `showSnackBar` — the law is owner-given.
- **The wake lands in the phone too**: setting the brief's wake on
  Android continues straight into the clock plant (pre-filled, clock
  opens so the person sees it land); the small replant button stays.
- **The privacy slogan left the app** (menu screen, desktop rail; the
  STT switch subtitle lost its free/private/no-cloud tail) — «זה משהו
  לגיטהאב לכתוב כפיצ׳ר». README already carries it.

## 2026-08-19 — שינוי שעה wears its name, and the Hebrew stopped commanding men

Owner: the routine postpone door «עוד היום» becomes **«שינוי שעה»**, and
the sheet must SAY the move is one-time — «לתת לאנשים להבין שזה חד
פעמי». Plus an open license: fix any copy that reads wrong.

- **שינוי שעה** (`later_today_door.dart`): door label + sheet title
  renamed; `showTimeFusionSheet` grew a `note` line under the title.
  Routine mounts (routine_tile, next_hero_card, caregiver home, and the
  long-press flow in main.dart) pass «רק להיום — השגרה הקבועה לא
  משתנה.»; plan mounts pass nothing — a plan's move IS the plan.
- **The gendered-imperative sweep**: every masculine command the UI
  spoke (הקלד / פתח / נסה / סרב / צמד / הפעל / השתמש / בחר / שים לב /
  תן / לחץ / הקש / סמן / חפש / סנכרן) is now the app's own voice —
  infinitives and plural doing-forms. Half the users this app is for
  are not men; the pairing dialogs, sync screen, and LAN toasts were
  the worst rooms. Test `pairing_dialog_test` updated to the new doors
  («לסרב», «צימוד מאובטח»).
- **Adult temperature enforced where the law already said so**:
  «זה בסדר גמור» left the didnt-happen sheet (AGENTS.md quotes that
  exact phrase as the counter-example) — it now says deciding counts;
  «כל הכבוד על הסדר» / «יש לך את זה» / «מדהים!» trimmed; the widget's
  default voice dropped את/ה slash-forms and «= ניצחונות גדולים» (kid
  and ADHD voices keep their chosen brightness).
- **One word for the helper**: «מטפל» unified to «מלווה» (routines
  screen, sync level-4 text — which also mis-named the Today button;
  it is «למלווה»). «מי שאתה מלווה» → «מי שבליווי».
- Smaller honesty fixes: «השלום לא נפתח» → plain words about the
  network listener; password mismatch says «הסיסמאות לא זהות»; broken
  .bns copy suggestions stopped commanding («אפשר לנסות עותק אחר»);
  «לא קרה + סיבה» → «לא קרה — ולמה».

## 2026-08-19 — The ear hunt: six field truths until the words landed

Owner: «ניסיתי הקלטה, המילים לא הופיעו — תבדוק בלוג איזו דלת ענתה».
Driven live over adb on the S23 (silent takes to fire the probe, the
Mac's own speakers speaking Carmit's sentence into a real recording),
ending with the words ON SCREEN: «שלום מה שלומך היום שלום מה שלומך
היום». What the phone taught, each fix in `MainActivity.kt` +
`android_file_stt.dart`:

1. **Doors are dynamic, not numbered.** The S23 has NO quicksearchbox
   RecognitionService. Its cast: AiAi (on-device host), **Speech
   Services (com.google.android.tts) — the winner**, and third parties
   we never touch. Kotlin `ears` lists them; the sidecar stores the
   door by name.
2. **ondevice has no Hebrew** (ERROR 12). When every door fails, the
   app now asks the engine to download the pack
   (`checkRecognitionSupport` + `triggerModelDownload`) — a later run
   may find a fully offline door.
3. **An fd session IS a segmented session.** Without
   `EXTRA_SEGMENTED_SESSION = EXTRA_AUDIO_SOURCE` the service returns
   an empty success in 500ms. Results arrive via `onSegmentResults`,
   joined per segment — this is also the long-recording answer.
4. **16 kHz only.** A 44.1 kHz feed dies as SERVER_DISCONNECTED /
   NETWORK; every take is linear-resampled to 16 kHz mono first.
5. **Pace the pipe.** Blasting 16s of audio at 100× folded the network
   layer (ERROR 2 in 40ms). Feed at ~4× realtime (1s of audio per
   250ms).
6. **Silence never answers.** A quiet take triggers no callback at
   all — after EOF a 20s wrap-up closes with whatever was heard, and
   the door is NOT forgotten (only door-shaped errors forget:
   `no_*`, 9/12/13, start-refused; network moods pass).
   Plus: legacy `iw` locales are spoken to the service as `he`.

Field-test leftovers, owner told: a few wordless test voice-notes
banked into Memories between 20:05–20:17 (his real 19:52 take was
deliberately saved); orphan test audio files on disk; media volume
restored to 94.

## 2026-08-19 — 0.17a: the ear inside, and one mouth for the mic

Owner (the same night as the hunt): "we find a way to sst less fragile
than android simple one that cancel itself when you press any point of
the screen... record package + any Whisper package." Built:

- **`WhisperEar`** (lib/services/whisper_ear.dart): whisper.cpp compiled
  INTO the app via `whisper_ggml` — Android, iOS, macOS, Windows, Linux,
  one ear, offline after one download, nothing that cancels itself
  because a finger touched the screen. Model = `small` (Hebrew is
  genuinely usable there; `base` mangles it — field truth 2026-07-27).
  Download lands under a `.part` name and only takes its real name once
  whole — a crashed download can never impersonate an installed ear.
- **`Ear`** (lib/services/ear.dart): ONE EAR FOR THE WHOLE APP. Rungs:
  WhisperEar → the platform's own file ear (Google/Apple) → the old
  desktop doors (whisper-cli exe, Vosk). Every rung answers '' rather
  than throwing; sttEnabled off = silence from every rung.
- **`VoiceTake`** (lib/services/voice_take.dart): ONE MICROPHONE, ONE
  PERSON. Every recorder in the app (capture room, every field mic)
  goes through it — the mic has one holder, a second asker is told, and
  nothing listens or stops on its own.
- **The field mic reborn** (dictation_mic_button.dart): no system popup,
  no live engine that dies on a pause — press, speak, press, and the
  ear reads the finished take («כותבים…» while it does). Hides itself
  when NO ear could answer. Capture room now records through VoiceTake
  and hears through Ear (dead code swept).
- **The settings door** (sync screen, under the STT switch): «אוזן
  משלנו — עובדת בלי רשת» — install (~490 MB, progress shown), remove.
- Android build: whisper_ggml's own module aims at compileSdk 34 while
  its ffmpeg demands 35+ — android/build.gradle.kts now raises any
  library module that aims too low (reflection, AGP-shape-proof).

v0.17a / 0.17.0+10 by the alpha law.

## 2026-08-19 — The sitting pile: the why that went blank, the + that invented, the window they could not see

The night's leftovers, worked in order:

- **Skip-why that could go blank** (the sharpest edge of the new ear:
  words land a moment AFTER the stop-press). A confirm pressed mid-take
  CANCELLED the recording — the spoken why died with the sheet; pressed
  mid-«כותבים…» it outran the words and kept a blank. Now every worded
  keeper settles the mouth first: `DictationMicButton.settle(controller)`
  finishes a running take, waits for the words, and only then does the
  door answer. Wired into the miss sheet (both doors, with an honest
  «כותבים את המילים…» on the confirm), the diary keep, the capture Save,
  and the new plan ask. Tap-out still cancels — leaving is leaving.
- **The calendar + stopped inventing plans** (Eagered's 03:07 ghost:
  a bare + auto-created «פגישה חדשה / הערה»). The + now opens the
  focused day with the ONE add ask up (`DayView(startWithAdd: true)`);
  the name field starts EMPTY with a mic, «הוספה» sleeps until a name
  exists, ביטול creates nothing. The «פגישה» prefill died too — a name
  answerable by silence is how ghosts are born. test/named_plan_test.dart.
- **The L2 window they could not see** (gBNS harness): LAUNCH.sh now
  seats the pair — Person LEFT, Care RIGHT, both raised, person
  frontmost. Lived on this Mac: the seating screenshot showed the person
  window wearing «היום מתחיל 15:00» — and CAUGHT a stale harness app:
  BNS-Care.app predated the data-dir pin and was answering the person
  question «מתי היום שלך מתחיל?» from bundle documents.
  scripts/deploy-all.sh now re-dresses the gBNS L2 pair with every wave.
- **The New Bot has a job**: COPY-AUDITOR.md — the queued full-app
  Hebrew copy audit as a seat charter (find, never fix; one report;
  the owner walks the findings).
- Eagered's capture-maze fix (forDate + «להוסיף רעיון ליום הזה») was
  already in the tree since 413dd6b — it needs LIVING on a current
  build, not building.
- One Care / few people stays REQUIRED and frozen (owner: do not start
  the switcher; sync frozen until L1 clean).

Tests 357.

## 2026-08-20 — STT everywhere, for real: the nine fields that had no mouth

Owner: "did we take the android advice and use sst like in android in
all the applications?" Audit answer: not yet — every field a person
writes in was supposed to wear the mic (the STT-everywhere law), and
nine did not. Now they do, through the one DictationMicButton / Ear /
VoiceTake mouth: the ROUTINES EDITOR (title, description, every step's
title and note — the biggest hole: you could not speak a routine's
name), the capture room's context field, the two search boxes (memories
«למצוא זיכרון…», day-thread «חיפוש מילים…» — wired through controller
listeners so a dictated word actually searches), and the sync screen's
share-name and device-name dialogs. Every one of their saves settles the
mic first (the skip-why lesson).

Deliberately still without a mic: the three caregiver-password fields
(obscured), the numeric pairing code, and the two typed-confirmation
gates («מקלידים את שם השיתוף») — deliberate typing IS their point.

## 2026-08-21 — 0.18a: the day starts when you wake

Owner: "I want the start of the day to start the routine just like in
normal day that you wake up like a normie, I want to push the entity of
the routine into whatever hour the user woke up... it just needs to move
to the day of a user that wakes up in different hours."

- **The routine is a shape** (`lib/core/wake_anchor.dart`, pure): its
  head is the usual clock of the first routine in person-day (owl) order.
  `wakeAnchoredTimes` slides the head to the wake hour and every routine
  of today follows by its own gap — quarter hours, nothing past the day's
  border; plans/events stay on the clock; answered rows stay; a row the
  person already moved today keeps their move. Today only, through the
  very `timeByDay` overrides שינוי שעה writes — so the list, הבא, the
  reminders, day view, the widget and the Care seat follow for free.
- **One קמתי per day** (`WakeAnchorService.anchorToday`): settings
  `wokeAt` = 'yyyy-MM-dd HH:mm' — a second press cannot shift the day
  twice. Fed by the ring popup's «קמתי ✓», the shade's «קמתי ✓» action,
  and the new Today door.
- **The door** (`WakeAnchorDoor`): «היום מתחיל ב-08:00 — קמת? הרשימה תזוז
  לשעה שקמת בה.» with «קמתי» / «עוד לא קמתי» (hushes until the next
  open; memory only, on purpose). Stands on top of Today while
  unanswered, like the unset day-start; answered, it is a quiet footer
  line «קמת ב-17:45 — הרשימה זזה לשם. רק להיום.» Guided and Care seats
  never see it.

v0.18a / 0.18.0+12.

## 2026-08-21 — The tidy: four stale root docs out, the L2 harness comes home

Owner: "I don't understand how so we are still having so many folders."
The folder was three things wearing one name: the source git holds (~400
files), ~12 GB of ignored build residue (build/, .dart_tool/, dist/, the
harness copies), and real clutter. The clutter went:

- **Four root docs that lived twice** — bns-format / ideas-for-
  handicapped-users / sync-security-and-progress / packaging-and-
  associations — root copies from July, docs/ copies current, every link
  already pointing at docs/. `git rm` of the root copies.
- **The L2 harness pair came home**: gBNS/.l2-test → bns/.l2-test next to
  its L3/L4 siblings (owner, 2026-08-17: "focus our files into bns folder
  not gbns"). LAUNCH.sh, both entitlements' sandbox path exception, the
  container pointers (bns_home.txt) and deploy-all's L2DIR follow; the
  apps were re-signed with the moved exception; `.l2-test/` joined the
  gitignore; a breadcrumb sits at gBNS/.l2-test-MOVED.txt. Lived: the
  pair launched from the new home, zero sandbox denies, both stores
  written at launch.
- Left alone on purpose: gBNS/ and grokBNS/ (nothing we use lives there
  now — archive or delete is the owner's word), `flutter clean` (~11 GB
  reclaimable, at the price of one slow rebuild).

## 2026-08-21 — The clean: the forks retired, the build residue gone

Owner: "the folders and files that are not needed lets remove them...
if its old cache needs refresh at some point its nothing for me to
rebuild you can clean it also."

- **gBNS/ and grokBNS/ (+ gBNS.zip) retired** — both remotes are
  github.com/WhiteNo1s3/grokBNS, so their committed history lives on;
  what the loop ever read from them (the Prototyper's iterate list with
  Eagered's notes, the seat files, the fork changelog) and each fork's
  uncommitted work as a text patch sit in docs/user-reports/forks-archive/.
  The trees went to the Trash (recoverable until the owner empties it) —
  not hard-deleted.
- **dist/ keeps only the living wave and the one before** (0.17a, 0.18a);
  0.11–0.16 artifacts went to the Trash too.
- **`flutter clean`** — build/ (7.6 GB) and .dart_tool/ gone; `pub get`
  restored the deps; tests run. The Flutter SDK itself
  (/opt/homebrew/share/flutter) stays — it is the toolchain, not cache.
