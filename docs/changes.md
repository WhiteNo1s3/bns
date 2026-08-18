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
