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
