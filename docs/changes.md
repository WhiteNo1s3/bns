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
