# The care levels — blueprints for 1–4

BNS meets people across a whole spectrum of need: from someone fully
independent who wants a calm memory tool, to someone for whom "when it
kills the brain only routines work." The **care level** is that spectrum
as ONE visible choice — the "Care level" card on the Sync screen, four
big radio rows, exactly one selected.

The level is the *story*; two flags stay the *source of truth* for
behavior: `fullCareMode` (level 3) and `guidedMode` (level 4, which
implies 3). The selector keeps story and flags coherent in both
directions — flipping a fine-grained switch re-derives the level, so the
card never lies (`_deriveCareLevel` in
`lib/features/sync/sync_screen.dart`).

Two laws frame everything below:

- **Sharing is ALWAYS the person's side of the wall** (owner, 2026-07-06).
  A level describes what *leaves toward the people who care* — never a
  filter on what the person themself can see. The person's own paired
  devices always carry the full day.
- **THE PERSON ANSWERS** (owner, 2026-08-15, from rehabilitation at
  Shiba; extended 2026-08-16). Done, skip, step progress and take-backs
  are born only on the person's own device — a caregiver device cannot
  write an answer at all. **Answering is available at EVERY level,
  including 4** — only *building* the list is ever locked to the helper.
  The voice is always WE ("לקחנו את זה?"), progress reads as readiness,
  and an answer can always be taken back.

---

## Level 1 — Independent

> "Independent — everything in your hands, nothing leaves this device
> unless you choose." / "עצמאי — הכול בידיים שלך, שום דבר לא יוצא
> מהמכשיר אלא אם תבחר."

**Who it's for.** The default, and the dignity baseline. Someone
managing their own memory — TBI, executive dysfunction, or just a hard
season — who needs the app, not a helper.

**What leaves the device.** Nothing, with exactly one voluntary
exception: the **Need-help close circuit** (`lib/core/need_help.dart`).
The person can open a Need-help ask on a routine or plan; only that
opened ask travels, carrying one sentence — "I asked for help on this."
/ "ביקשתי עזרה בזה." — plus the named item. A skip, a late tick, a
mood, a location, or silence is NEVER an ask; skip-derived `need-help`
diary notes must never look like one (`isSkipNoteNotAnAsk`). The
caregiver/family window maps to `FamilyShareLevel.asksOnly`.

**What the person can do.** Everything. All four doors (Today / Keep
this / Memories / Calendar), full editing, full building of days.
Reminder loudness is their own choice (the level 1–2 notifications
wave). Mad-mode, quiet mode, all of it — theirs.

**What the helper sees.** Only an opened ask, if the person opened one.

**Doors.** No guard in any direction. Moving between 1 and 2 is free.

**In the code.** `careLevel = 1` (default), `guidedMode = false`,
`fullCareMode = false`, `careLockHash` empty.

---

## Level 2 — Family knows the important things

> "Family knows the important things — chosen plans go into the family
> file." / "המשפחה בעניינים — תוכניות שבחרת נכנסות לקובץ המשפחה."

**Who it's for.** Someone independent whose family should know the
important things — appointments, chosen moments — without seeing the
private texture of their days.

**What leaves the device.** Only what was chosen, item by item: events
marked "family can know" (`shareWithFamily`) + moments tagged `family`
(their voice notes ride along) + opened Need-help asks. Nothing else
exists in the family file, no matter how it's opened
(`BnsExporter.exportFamilyShare` — a filtered EXPORT, never a filtered
view). A `mad-vent` NEVER enters a filtered share even if tagged — a
rage-moment decision to share must not outlive the rage; while a storm
is being vented, capture doesn't even offer the family switch. A
deliberate share of a COOLED storm is designed but not decided — the
"cooled storm door", ideas wave 26, awaiting the owner's yes. Maps to
`FamilyShareLevel.chosenFamily`.

**What the person can do.** Everything — level 2 changes only the width
of the window, never the person's own app.

**What the helper sees.** The family file / family view in the
Explorer and web satellite: the chosen plans and moments, read-only.

**Doors.** No guard. Raising from 1 or lowering to 1 is one tap.

**In the code.** `careLevel = 2`, both heavy flags off, no lock.

---

## Level 3 — Full care (`fullCareMode`)

> "Full care — the people who care see everything, including the hard
> moments." / "ליווי מלא — האנשים שאכפת להם רואים הכול, כולל הרגעים
> הקשים."

**Who it's for.** The last resort for the severely impaired — "people
with their name and number on their back in rehabilitation." Decided
together, never imposed.

**What leaves the device.** EVERYTHING — every plan, every routine,
every moment, every voice note, **the rants included** (owner explicit,
2026-07-08: the frustration IS the signal — "annoyed at the elevator"
is how you know to help with elevators; hearing it in his own voice IS
the information). Maps to `FamilyShareLevel.fullCare`. The rants travel
to the HELPER only: on the person's own device, storms still never come
back (caregiver-robot report, fixed 2026-08-16 — the day diary showed
vents to a level-3 person because `includeMad` keyed on `fullCareMode`
alone; vents now show only where the helper is, or while the person's
own mad mode still burns).

**What the person can do.** Their app is unchanged: full editing, full
building, all doors. Level 3 opens the window wide; it takes nothing
out of their hands. Their ✓ / skip / step answers remain theirs alone.

**What the helper does.** MONITORS, never edits — the family view stays
read-only. The inspector may build the day and watch it, but done,
skip, and step progress arrive only by sync from the person's device;
the store itself refuses answer-writes on a `caregiverDevice`, the Care
calendar shows state as a fact instead of a checkbox, and reminders
never ring in the helper's pocket.

**Doors.** ON is guarded: typed share-name confirmation, decided
together, and as part of raising, the caregiver chooses **the
caregiver's key** with the person (`careLockHash` — salted hash only,
the password itself never exists on disk). OFF / lowering opens with
that key (owner decision 2026-08-15: the lock is what lets the
caregiver NOT hover — without it, one confused tap dissolves the
arrangement and the hovering returns). A device from before the lock
(empty hash) still lowers freely. Leaving to level 1–2 retires the key.
The person's own ANSWERING is never behind any lock.

**The attitude, in the owner's words.** "dad, write things that annoy
you — this is the list, we build it together, you select what's done
and what's not, we will adjust and comply with anything that helps you."

**In the code.** `careLevel = 3`, `fullCareMode = true`,
`guidedMode = false`, `careLockHash` set.

---

## Level 4 — Guided (`guidedMode`)

> "Guided — only the list. The day is built by the caregiver." /
> "מונחה — רק הרשימה. את היום בונה המלווה."

**Who it's for.** When routines are what remains (owner design,
2026-07-08, from a Holocaust survivor's kid with Alzheimer's: "when it
kills the brain only routines work"). At this stage choice is a burden,
not a freedom — the app gives instructions, not choices, delivered with
love, never as control for its own sake.

**What leaves the device.** Everything — enabling level 4 auto-enables
level 3, so the inspector sees all of it (`FamilyShareLevel.fullCare`).

**What the person can do.** Their device shows ONLY the list — big and
visual (Today renders big tiles; keyboard shortcuts shrink to
mark-done / open-today / tell-something; wandering off Today surfaces a
way home). They CAN:

- **tick a task** — with the gentle "Is it done?" acceptance, tracked
  for both the person and the inspector;
- **long-press to tell about a problem** — voice or writing, always
  saved.

They CANNOT: add, edit, or delete routines or events; build a day;
change order. Answering stays theirs — see THE PERSON ANSWERS.

**What the helper does.** The INSPECTOR (the caregiver's paired device)
builds and edits everything; changes arrive over LAN auto-sync under
the directional law **RECEIVE FIRST, THEN SEND** — pull the person's
truth, merge, only then push the built day. The person's device remains
the source of what HAPPENED; the Care side is the source of what is
PLANNED.

**Doors.** Same key as level 3: ON via typed share-name confirmation +
choosing the caregiver's key together; OFF opens with the key. The
caregiver door on Today (long-press) opens with the key too. Cancelling
any step of a raise leaves everything exactly as it was — a raise never
completes half-way.

**In the code.** `careLevel = 4`, `guidedMode = true`,
`fullCareMode = true`, `careLockHash` set. `CareState.guided` gates the
UI app-wide.

---

## The machinery (shared by all levels)

- **Storage.** `AppSettings.careLevel` (int, default 1) +
  `guidedMode` + `fullCareMode` + `careLockHash` in
  `lib/core/models/settings.dart`. Pre-`careLevel` stores migrate on
  read: guided → 4, full care → 3, else 1.
- **Selector coherence.** `_setCareLevel` in
  `lib/features/sync/sync_screen.dart`: raising to 3/4 rides the
  guarded flows (typed confirmation, then `_ensureCareLock`); lowering
  out of a locked 3–4 opens with the key; dropping to 1–2 turns both
  flags off and retires the key. The fine-grained switches below the
  card honor the key too — they are not a way around it — and after any
  switch the card's level follows.
- **Share mapping.** `familyShareLevelFor` in `lib/core/need_help.dart`
  is the single law for what a caregiver/family window may receive:
  1 → asks only, 2 → chosen family, 3–4 → full care. Own devices (peer
  not a caregiver) always get the full day.
- **The helper does not become the person — and hats never travel at
  all (2026-08-17).** On merge and restore, a `caregiverDevice` keeps
  its OWN hat — role flags, care level, share name, and the key never
  adopt the person's (`lib/data/local/isar_service.dart`, caregiver
  report 2026-08-16). The reverse holds too: a person's device pulling
  a Care store never adopts the helper's flags — adopting Care's
  `guidedMode=false` would have silently opened the level-4 cage on
  the next auto-sync. Care flags cross only between the person's own
  devices. Three more walls from the same day: the router's
  containment rule ignores a helper's device entirely
  (`CareState.containmentRedirect`), a store that still carries the
  pre-fix contamination (`caregiverDevice && guidedMode`) heals at
  load, and flipping a device to caregiver clears `guidedMode` on the
  spot. `test/care_containment_test.dart` holds all of it.
- **Every level keeps the non-negotiables.** Adult temperature, no
  punishment language, static screens, labeled doors, 48dp targets,
  LAN-only privacy — the level changes who helps, never how the app
  speaks.

## Beyond the four

- **`caregiverDevice` is a role, not a level** — it marks the helper's
  copy (builds the other person's day, never nags its holder, cannot
  write answers). Any level can exist on the person's side of a pairing.
- **BNS Care** (owner, 2026-08-16 night) — care work is becoming its
  own entry point from the same repo, multi-profile, wrong-profile push
  impossible by structure. See ideas wave 23.
- **"Level 5" — the sketchbook** (ideas wave 22, DESIGN ONLY, awaiting
  the owner's yes): a caregiver-only profile with no pairing at all,
  for the household where the person will never hold a device — the
  helper's pocket is the only pocket. Not in the app today.
