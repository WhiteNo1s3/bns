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

- ~~**Two maps on the phone**~~ — RESOLVED by owner rule (2026-08-16):
  doors hold the main rooms (Today / Keep this / Memories / Calendar),
  the ☰ menu holds only the rest (day words / my routines / settings),
  and Today's body carries no second copy of any room. Guided mode is
  the lone exception: no doors, no menu — the capture bar and the
  key-gated Settings door live on Today because there is nowhere else.
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


## Caregiver problems pass (docs/user-reports/2026-08-16-caregiver-problems.md)

Fixed same day:
- **Vents shown back to the level-3 person in the day diary** — includeMad
  keyed on fullCareMode alone; now vents show only where the HELPER is
  (caregiverDevice) or while the person's own mad mode still burns.
- **Doctor-row tap silently family-shared a medical plan** — a plain tap
  never shares; the row opens the bag ("מה לוקחים?"), sharing stays on
  its own icon.
- **First sync copied the person's identity onto Care** (shareName=Ben,
  guidedMode, careLevel=4) — a caregiver device now keeps its own hat
  through merge AND restore: role flags, share name, caregiver key.
- **The bag had no door when empty** — the backpack shows on every open
  plan now; an empty list is where the list gets built.
- **Care at phone width lost the routines room** — the helper's doors
  swap "Keep this" for "Routines".

Noted, stale-build (their .l4-test apps predate the caregiver's key):
- מלווה long-press CRUD leak — already key-gated in main (wave 21).
- Restart-lands-on-Sync — one-map + guided containment supersede.

## Harness rebuild day (2026-08-16 afternoon)

Fixed same day:
- **Sync identity roulette — the real pairing-killer found.** Every
  instance claimed TCP 42425 in its hellos while only one owned it; on a
  machine running siblings (Person + Care on the Mac, all four harness
  apps) a PULL could land on the wrong instance, whose honest "REVOKED"
  (I don't know you) the requester OBEYED — erasing a living pairing.
  Watched it happen: all four harness stores wiped their trusted lists
  within seconds of launch. Now every instance binds its own door
  (42425..+8, else ephemeral) and announces the real number; PULL2 names
  the expected server, strangers answer NOTME, and the severing word is
  only valid from the device it names. Legacy PULL (older phone builds)
  gets silence instead of REVOKED — it can no longer erase anything.
  This also explains the phone/Mac trusted-list disagreements and the
  banner snapping to "עדיין לא מחובר" — most of the "sync identity"
  mystery was this one bug. Still open from that chunk: name-row
  duplicates when a device is reinstalled (ghost entries).
- **Caregiver cannot set done (owner reversal, 2026-08-16)** — the
  helper's device builds and watches; ✓/skip/steps/take-backs write only
  on the person's device and arrive by sync. Guarded at the store, shown
  as fact (no checkbox) on the inspector's calendar, dead provider path
  deleted. Covered by test/caregiver_answers_test.dart.
- **.l4-test/.l3-test bundles rebuilt from current code** (they predated
  the caregiver key, one-map, postpone, tone, banner, everything).
  Same bundle ids, same stores, ad-hoc re-signed with the harness
  entitlements. L4's erased pairing restored from the .bak files;
  verified live: four instances on four ports, pairing surviving
  auto-sync crossfire, Care banner green "מחוברים ל־Ben — נשמע לאחרונה".

## Night pass (2026-08-16 evening — caregiver-problems.md + owner directives)

Fixed same night:
- **"In the L4 pair nobody can postpone"** (tester) — later-today
  (`timeByDay`) ported from the gBNS working folder on merit (its base
  was old; only the feature slice came over: pure slot logic, model
  override, reminder one-shot + fingerprint, 15 ported tests). Doors
  wired where they belong: person tiles + plans + the Next hero
  (hidden in guided mode), AND the inspector's rows — «עוד היום» under
  every open routine on Care, writing a one-day override that syncs to
  the person, whose own device re-registers the reminder by itself.
  Moving the clock is day-building (the helper's hand); the ✓ stays
  the person's.
- **"Green and blue are making me sick"** (owner) — the palette family
  is warm now: clay (terracotta) is the app's face; lavender, sand and
  rose stay; teal and deep are GONE (stored old values fall back to
  clay). The dark base itself was green-cast (0xFF171D1B) — now a warm
  deep (0xFF1E1916); light paper warmed a step too.
- **The garden forgot "remember"** (owner: "it should be saved for
  them to remember") — retention silently ate `remember`-level
  captures after 14 days. Now only passing `quick` notes roll off;
  `remember` and `memorize` are permanent, promoted vents included.
  test/garden_saved_test.dart.

Directions taken (design written, build next):
- **BNS Care becomes its own app** (owner) — multi-profile (nurses,
  two children), one store+pairing per profile so misfires are
  structurally impossible, RECEIVE-first-THEN-send directional law.
  Ideas wave 23 + AGENTS law; folds in the tester's "one Care cannot
  hold two people" and wave-22 sketchbook.
- **Garden looks** — wave 24: words-first cards, planted vs. passing,
  months as beds, no counts anywhere.

## Marks + the wall audit (2026-08-16 evening — owner directives)

Built same evening:
- **The marks (tagging) system got hands** (owner: "improve to maximum
  the tagging system which doesn't exist in practice in any of the
  versions" — verified true in bns, gBNS and grokBNS alike). Chips to
  choose a mark at capture, a person's own word, marks editable later on
  the kept memory, flair on every Memories row, filter-by-mark, and
  search that speaks the person's language («משבר» finds `crisis`).
  Wave 25; test/tag_flair_test.dart. Riding along: `asked-help` wears
  words now, `day-idea` joined plumbing, and a live vent no longer
  offers the family switch (filtered exports strip mad-vents by law —
  the switch was a lie).
- **Vents-to-family question** (owner) — answered as design, not code:
  the cooled storm door, wave 26, awaiting the owner's yes.

Understood, open — found while answering the vents question:
- **The care wall is thinner in code than in law.** The family FILE has
  only two widths (chosen / full-care everything); the Level-1
  "asks only" window and the ask-notify (`need_help.dart` share side)
  have ZERO callers; and **LAN sync ships the person's FULL store —
  vents included — to every trusted device at every care level**, so a
  paired Care device at level 1–2 already holds everything and its home
  shows the rants. The per-level caregiver window exists as law
  (`familyShareLevelFor`) and not as plumbing. Belongs to the BNS Care
  build (wave 23, RECEIVE-first-THEN-send); recorded in bns-format.md
  so the doc no longer overclaims.

## Keep-and-find pass (bns-test/qa-keep-find.md, 2026-08-16 night)

The loop itself PASSED on Android L4: keep a Hebrew thought, find it
first in Memories, family tag survives reload. Their two "bugs to own
later", owned the same night:
- **"Save promises 'אני אראה את זה' but lands on Today"** — the promise
  was a leftover navigation hint. The button now makes the void-promise
  without it: «שמירה — זה נשאר אצלי». Landing on Today is design (the
  kept strip is the seeing); now the words match.
- **Family-share switch hidden under the guided "חזרה ליום שלי" bar** —
  opening the options door now brings the switches into view by itself
  (static jump, no glide).

Open / recorded:
- **Version-skew data loss**: the 15-Aug debug APK strips `gather` on
  save (old models rebuild JSON from known fields). Same risk class for
  every new field. Future hardening: unknown-key passthrough in models.
- **Pruned captures orphan their audio files** on disk — cleanup pass
  wanted alongside the garden work.
- **dayStartHour setting has no picker yet** (model + logic in; the
  person's day start defaults to midnight until a settings door lands).
  Alpha rule meanwhile: kill stale builds after a schema wave.
- Windows person build shares the live Mac Documents store; Windows
  rebuild broken (MSBuild VCTargetsPath / ARM64). Alpha-env only.
- Ctrl+R once landed on /sync — unreproduced.
