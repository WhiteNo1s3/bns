# Level-1 night triage (reports of 15–16 Aug 2026)

## The wall, the maze, the marks (2026-08-17, third pass — 219 tests green)

Owner: "the caregiver gave problems... solve those as soon as possible...
giant bugs like the maze and the lan sync dumping full store... the
tagging system needs a work, its gotta be fluent."

- **THE PER-LEVEL SYNC WALL IS UP.** LAN sync used to ship the person's
  FULL store — vents included — to every trusted device at every care
  level. Now a peer wearing the helper hat gets the CARE WINDOW the
  person's level allows: level 1 → opened asks only; level 2 → chosen
  family plans + family moments (vents never, even tagged); levels 3–4 →
  everything active, rants included (the law). Every window ships a
  settings STUB (shareName only) — identity, keys and preferences never
  cross toward a helper, so a hat cannot travel inside a window at all.
  The hat is learned two ways: the helper's own PULL2 names it
  (receive-first law ⇒ even a fresh pairing's FIRST answer is already
  filtered), and every full store a peer sends teaches it (deviceId must
  match the sender — a window stub can never teach). Own devices sync
  full, exactly as before. `careWindowFor` in sync_policy;
  `exportCareWindow` in the exporter (the family share now delegates to
  it); `TrustedDevice.peerIsHelper`. test/care_window_test.dart.
  Transition note: an OLD Care build that never declares and never
  pushes keeps getting the old full store until it sends once — rebuild
  the harness Care apps.
- **THE ISOLATION DOOR IS REAL.** `--data-dir PATH` / `--data-dir=PATH`
  / `BNS_DATA_DIR` pin a process to its own home; the live
  `bns_home.txt` pointer is neither read nor written while pinned. The
  Windows-seed-overwrote-the-live-store class of accident is closed by
  structure. test/bns_home_isolation_test.dart; testing-live.md updated
  (it documented the flag a day before the flag existed).
- **THE CAPTURE MAZE, UNTANGLED.** One Save now — the header שמירה is
  gone, and the one worded Save is PINNED under the screen, riding above
  the keyboard (it lived mid-scroll with zero inset handling). A
  double-tap cannot save twice. Cold-open stale text explained and
  fixed: go_router reuses the screen's State when /capture is asked for
  while already open — a widget-press or door-press now asks for a
  FRESH visit; leftover words are BANKED as a kept thought first (words
  are never lost), and autoRecord is honored instead of silently
  skipped. Dictation mic on the words box itself. Spoken words land on
  the take that asked for them, not whichever take is newest.
- **MARKS OFFER THEMSELVES (the fluency idea).** The marks are already
  in the person's words — so the app reads the words and offers the
  matching marks as one-tap chips right above Save, no disclosure to
  open: their own past words lead (Hebrew prefixes come free), built-ins
  match by label in either language (English whole-words only), reserved
  doors (family, storm) never volunteer, nothing is ever auto-applied,
  three at most. The picker also remembers the person's whole mark
  VOCABULARY now — a word invented yesterday is one tap today (it used
  to live only on the moment it was typed on). A mic on the own-word
  field (voice-first), no more partial-word commits on stray taps, and
  typing "family" can no longer silently trip the export path.
  suggestMarksFor / ownMarksOf in tag_flair; test/mark_suggest_test.dart.

Caregiver-problems file status: every item is now either fixed (identity
copy → four walls; phone-width routines door; doctor-row tap; bag door;
vents leak; מלווה leak key-gated) or structurally closed this pass
(full-store dump → the wall; Windows live-store overwrite → the pin).
Still theirs: ghost duplicate rows after reinstall + trusted-row rename
(sync-identity chunk), Android emulator isolate (use --data-dir now).

## PR1 + the level-1 note (2026-08-17, second pass — 196 tests green)

The Prototyper's PR1 (`prototyper-doors` on grokBNS) reviewed on merit
and PORTED: didnt_happen (dismiss-with-words IS the skip), PairingGate +
pairAskDisposition, DayLookTile, the didnt-happen sheet, and five test
suites. Two honesty notes: `look_only_test` was RED on its own branch —
it imports person-day functions nobody had written; they were written
HERE (owl_time: isFuturePersonDay / lookOnly / hasNotCome /
offersCompleteOrSkip) and now hold. `pairing_dialog_test` wanted the
decline renamed «סגירה»; our «סרב» matches the dialog's own body copy
and stayed — test adapted. PROTOTYPER.md / changes.md were not imported
(fork-owned).

From `gBNS/level1problems.md` (the note), fixed in bns this pass:

- **"מחר בלי וי ובלי עיפרון. רק להסתכל"** — future-day routine rows are
  DayLookTile now: name + time, no box, no pencil; a tap says the day
  can wait. And "future" runs on the PERSON'S clock: at Saturday-night
  02:00 (day end 05:00), Sunday is still tomorrow — look-only.
- **"הסיבה נעלמת"** — the dismiss law everywhere: Today's miss sheet
  closing with words LOGS THE SKIP with those words (unless a door
  already answered — postpone stays postpone, never a silent skip);
  DayView's skip lost its capture-screen detour (the "empty save screen"
  thrower) and uses the one sheet; the English 'Skipped: ' prefix is
  gone from new records.
- **"בוצע = וי. אף אחד לא שואל שוב"** — Today's routine ✓ and plan ✓
  are QUIET now (no «זה נעשה?»); the one ask that stays is
  consent-over-notes (their own words shown before done-over-a-problem)
  and take-back. DayView got this last pass.
- **"צימוד כשלא ביקשתי" / "דף צימוד לא על בוצע"** — an already-trusted
  device asking to pair stays QUIET (deaf sync is not a reason to
  re-pair); a pairing ask waits for a mid-answer person (PairingGate
  around ✓/take-back/miss-sheet); a leftover extra copy cannot stack a
  second sheet; one showEnterCodeDialog door for the whole app.
- **"לוח שנה משקר"** — the month's day-preview now tells the day whole:
  plans AND the routines that apply (it showed one plan while Today
  carried the real list).

Still open from the note (owned, not lost): the capture maze (cold-open
stale text, keyboard over Save, two Saves, Hebrew-after-recording
append) — the capture wave; ghost caregiver rows + trusted-row rename —
sync-identity chunk; ☰ sometimes dead + "nav ate done" + FAB-on-doors —
need live repro on THIS build; ghost 03:07/05:00 events — one-time data
tidy; בוצע screen-reader name — semantics pass; iOS app — no conflict
markers remain anywhere, it simply needs a rebuild (ask when wanted).

**The real backdoor, named (for the BNS Care wave):** LAN sync ships the
person's FULL store — vents included — to every trusted device at every
care level. `familyShareLevelFor` (1 → asks only, 2 → chosen family,
3–4 → everything) exists as law with ZERO sync callers. Now that hats
never travel, the peer's helper-hat is honest data: the send side must
filter what leaves by the person's level whenever the peer wears it.
That filter is the centerpiece of the BNS Care build (wave 23), next.

## The stuck day + the jailed helper (2026-08-17, owner urgent)

Fixed this pass (all 169 tests green):

- **"I cannot return when I am at a day in the future... correct it with
  a return button"** (owner — Android, Mac, Windows). Yesterday's fix
  kept the bar, but the way back was still an arrow GLYPH among four
  unlabeled icons, and «להיום» only re-dated the same room. Now a worded
  «חזרה» is PINNED under the day on every platform and width, and it
  actually LEAVES — one pop back to the room the day was opened from
  (calendar / Today). The bar went words-only («להיום», «יומן»); sync
  and mic doors left it (wrong-room dump / duplicate of the body's
  worded capture button), add-plan moved into the body WITH the events
  list it adds to. Day title shortened (it was clipping). The pep-talk
  card above the day is gone; the done-count sits with the routines as
  a fact («2 מתוך 4»). And done in the day view is a QUIET ✓ — no
  «בוצע?» second question; only take-back still asks.
  `test/day_return_door_test.dart` (first widget tests in the suite).

- **"The caregiver becomes level 4 user — this is not acceptable"**
  (owner). The own-hat merge fix (2026-08-16) stopped NEW adoption but
  PRESERVED existing contamination: a Care store that already said
  `guidedMode=true` (the .l4-test Care restored from .bak is one) kept
  it forever, and the router's containment rule jailed the helper at
  `/` — the inspector locked out of building the very day. Four walls
  now:
  1. The containment rule ignores a helper's device entirely
     (`CareState.containmentRedirect` — testable, one place).
  2. A contaminated store (`caregiverDevice && guidedMode`) HEALS at
     load; flipping a device to caregiver also clears guided instantly.
  3. Hats never travel in EITHER direction through merge. The reverse
     hole was real and one build away: after the own-hat fix, a person
     pulling Care's healed store would have adopted `guidedMode=false`
     — the level-4 cage silently opening at the next auto-sync. Closed
     before it ever reached a build.
  4. `CareState.guided` is fed as `guidedMode && !caregiverDevice`, so
     even the in-memory moment before a heal persists cannot jail.
  `test/care_containment_test.dart`. Leftover cosmetics on contaminated
  Care stores (shareName=Ben, careLevel=4 in its settings display) are
  NOT auto-healed — display-only, owned by the BNS Care build.

- **Stale-build reality (why "it won't work on android, mac, windows"):**
  the Windows exe cannot carry ANY fix (rebuild broken: MSBuild
  VCTargetsPath / ARM64, source is the VM's gBNS); the emulator APK is
  from 15 Aug; the S23 and Mac apps predate yesterday's day-bar fix.
  Fresh builds made this pass: `dist/` macOS zip + signed release APK.
  Tomorrow's test must run on THESE.

Cross-tree (gBNS `PROTOTYPER.md`, read 2026-08-17): its "quiet ✓ / no
unlabeled day-view row / no pep talk" items are DONE here in the day
view (Today's own quiet-✓ remains gBNS's iterate). Its other open items
already live in this ledger: skip-reason must stick (miss-sheet race),
LAN re-pair sheet for a trusted phone (sync-identity chunk), the
capture maze, late-day proof on the S23.

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
