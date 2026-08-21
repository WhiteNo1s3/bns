# GROK.md

BNS (this folder is the silk / gBNS tree). Privacy-first Flutter app for routines, memory, reminders, voice. Built for neurological challenges (TBI, executive dysfunction). Hebrew-first. Android is the flagship.

Read **AGENTS.md** first. Those laws win over this file.
Read **changes.md** for what shipped in the 2026-08-14…15 iterate (file-ear, system clock, plans in Next, later-today, person-day). That is the test brief for every model.

## Who you are helping
The owner is the user. Level 1–2, Hebrew, late day (can start 15:00, end 05:00). Support, never punish.

## Commands
```bash
flutter pub get
flutter test
# phone: flutter run  (Android S23 is the live check)
```

## Hard no
- No cloud, no accounts, no analytics, no cloud STT.
- Never live STT + record at the same time on Android.
- No motion / slide transitions.
- No unlabeled icon rows. 48dp labeled doors.
- Never shame ("you missed", streaks, red X).
- Never hardcode a city timezone. The phone's clock is the clock.
- Do not start L3/L4 chrome, doctor-share, or servers unless asked.

## How to change things
- Models are hand-written Dart (`toJson` / `fromJson` / `copyWith`). No codegen.
- Persist through `lib/data/local/isar_service.dart`. Roundtrip `.bns` after data changes.
- Copy for the PERSON via `L.t(english, hebrew)`.
- Update `docs/ideas-for-handicapped-users.md` when a parked line ships.
- Append a dated block to `changes.md` when you ship something testers must check.

## Testers (Grok, Claude, local)
Claude Code: this repo has `CLAUDE.md` (same door). Work from `changes.md`. Each block has files, the feel, and a live-test question. Do not invent extra features in a test pass. Report: did the live-test pass, what broke, what you changed.

Iterate list (what to build next): **PROTOTYPER.md**.
