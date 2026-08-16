# Level-1 night triage (reports of 15–16 Aug 2026)

The reports in this folder are the raw truth from live use. This file is
the honest ledger: what was fixed, what is understood-but-open, and what
is not yet even understood. Nothing here gets to quietly disappear.

## Fixed (commit of 2026-08-16)

- **Words typed, Save pressed, note gone** (`sunday_tinker`) — the exit
  paths from capture could discard silently. Now a box with words in it
  ASKS before any leave-without-save, whatever weird route triggered the
  exit; a root-level Save lands on Today where "What you kept" proves the
  save. (The navigation weirdness itself — header Save landing on Sync —
  is still under repro, below; the guard makes it harmless.)
- **"Tab says Today while you are in Menu or Sync"** — off-map, no door
  claims selection anymore (indicator disappears instead of lying).
- **"08:00 saved as 10:15"** — add-event time was a prefilled text field
  that typing APPENDED to. It is a clock now.
- **"Rename to Phone typed, did not persist"** — the keyboard's enter
  never saved and outside-tap dropped it. Enter saves now.
- (Earlier same night: FAB clearance, level-4 containment, "הקלטה 1"
  stub, doors sizes — see waves 19–21.)

## Understood, open, next in line

- **Two maps on the phone** (☰ menu + 4 doors + old header buttons in
  places). One navigation story needs choosing; the menu and doors both
  arrived this week. Owner call wanted here.
- **Three Dones** (tile ✓ + FAB + "זה נעשה?" dialog asking again after a
  step flow) — consolidate: a deliberate step-finish should not re-ask.
- **Mac pairing window loops for an already-trusted device** + phone/Mac
  trusted lists disagree + "extra instances appear as extra caregivers"
  (alpha-only but confusing). Sync identity needs a stable device-id
  handshake instead of name-based trust rows. Biggest open chunk.
- **Miss-reason sheet can vanish before "זה לא קרה היום" is pressed**
  (keyboard/focus race) — the typed reason must survive the sheet closing,
  same law as the capture guard.
- **מילות היום leftovers**: broken `10:15` plan title concatenation from
  the old add-event bug lives on in saved data; needs a one-time tidy.
- **Journal "לחזור להיום" shows on today itself**; day title clipped;
  unlabeled icon row on the day screen.
- **Step-button a11y** ("החלק הזה בוצע" invisible to screen readers) —
  semantics pass on the hero card.
- **Memories and מילות היום share an icon** — give the journal its own.

## Not yet understood (needs repro before believing any fix)

- **"☰ often dead"** — menu button sometimes unresponsive.
- **Header שמירה jumped to Sync** — the guard above makes it lossless,
  but WHY the tap landed there is unexplained.
- **"Back from capture left BNS into a shopping WebView"** — likely the
  system speech sheet's task stack; watch for recurrence.
- **"Nav ate Done (meds 1/3→3/3 while in Settings/Menu)"** — steps
  advanced with no visible cause; could be the earlier FAB overlap.

## Explicitly out of scope for the app

- Editing `bns_data.json` by hand (level-4 report #7) — recorded in wave
  21 as future platform-keystore hardening.
