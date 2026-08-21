# Level-1 night triage (reports of 15–16 Aug 2026)

## L2 day-start door saw 15 on disk and still asked (2026-08-18 ~19:16)

Lived isolated L2 Person (0.14a / 04c0bf7). Person
`~/dev/gBNS/.l2-test/person/bns_data.json` and Care sitting רמה 2 both
`dayStartHour=15`. Today still showed «מתי היום שלך מתחיל?». No
הגדרות. No tap. No auto-write.

The running `com.whiteno1se.bns.l2person` .app was opening the bundle
documents (unset 0). macOS `open` never hands Dart `--data-dir` /
`BNS_DATA_DIR`. A dressed `.lN-test` app now pins its sibling
`person/` / `caregiver/`. Today paints `_dayStartHour` on the settings
frame so a loaded 15 cannot keep the question. Door already worded when
passed hour != 0. 0 stays unset. Confirm still writes.

test/bns_home_isolation_test.dart, test/day_start_persist_test.dart,
test/day_start_door_test.dart. docs/testing-live.md, docs/changes.md.
PROTOTYPER.md / GROK.md / CLAUDE.md are not in this repo (fork-owned).

## The no-dead-end guarantee (2026-08-18, sixth pass — 280 tests green)

Owner, lived: stuck in routines as caregiver at a narrow window ("no
return button... why no hamburger on each page"), and Android back
from a day view EXITED THE APP. Two structural holes, closed as laws:

- **A bar may step aside only when the sidebar is actually there.**
  `hideOnDesktopWide` hid by PLATFORM alone — below 820 there is no
  sidebar, so routines / the day thread were doorless rooms at any
  narrow desktop width. The bar now asks the WINDOW its width (same
  truth for preferredSize and build): narrow desktop keeps the bar and
  its ☰/back; wide lets the sidebar own the chrome. Every page carrying
  the flag inherits the fix at once.
- **Back never exits from an inner room.** The shell wraps every routed
  page: pushed screens pop normally first; system back from a routed
  room that is not home goes HOME; only home hands the gesture to the
  system. The "pushed back on android, it exit the program" class is
  closed everywhere, not per-screen.
- **Routines wears the worded return** when pushed (same pinned «חזרה»
  as the day view) — the caregiver's "where is the return button?",
  answered in words.
- test/no_dead_end_test.dart (bar-width law both sides; back-goes-home
  and back-at-home both directions).

Owner direction, same message: stop swallowing sync features whole —
stabilize. The wall + profiles stand tested and STAY; new sync scope is
FROZEN until the level-1 day runs clean (the reports' L1 list is the
queue: reach on Today, the miss-door count, hero confirm, FAB seat).

## The clock without the wall (2026-08-18, fifth pass)

Owner: "the picker of hours states all the times... less nightmare to
look at a long list... a fusion of our extra-15-minutes wonderful ui
and the time on the side to scroll... the caregiver should have the
knowledge and the option to set times for level 3–4 users as they are
not really feeling time the same."

- **TimeFusionPicker** (`lib/ui/widgets/time_fusion_picker.dart`): the
  chosen time BIG in the middle, an hour rail beside it to scroll and
  tap, postpone-style ±15 buttons for the quarter step, one confirm
  wearing the time. Replaces every hour-chip wall: the Today day-start
  door (now one worded button; once set it quiets to a small tappable
  line — changeable without הגדרות), and Sync's two walls (day start /
  day end — the end rail shows only 00–06).
- **THE INSPECTOR'S HAND**: the Care home (per sitting profile) shows
  «השעון שלהם» — set start + end in two sheets, written into the
  profile store, carried by the next round. `adoptPersonDayHour` now
  lets a helper's CHOSEN hour through **only when the person is under
  full care/guided** (L3–4 — moving the clock is day-building); a
  helper's 0 is never a choice, and an L1–2 person's clock stays
  theirs alone. The caregiver holds the aligned day the midnight
  report asked for ("Caregiver must have that day aligned and known").
- test/inspector_clock_test.dart (rule edges, merge end-to-end, sheet
  widget tests).

Still open from the night reports: the student's reach (capture / עוד
היום / skip too far from Today at L2), the four-door miss sheet on old
builds, S23 needed this build (deployed this pass).

## Care profiles, wave 1 (2026-08-17, fourth pass)

Owner: "we need profiling system for the caregiver... flawless diamond
... choose from dropdown the profile, it will host many bns files and
we keep the loop perfect." Caregiver report REQUIRED section, same day.
The law: docs/care-profiles.md. Shipped:

- **A profile is a person** — its own complete home under
  `profiles/<id>/` (store, audio, trusted[], pairing, level). The trust
  row IS the address book, so a wrong-profile push has no code path.
- **The sitting**: a worded dropdown on the Care home («אנשים») lists
  every named door + «אדם חדש...» (name speakable — mic on the field).
  Choosing swaps the ACTIVE store wholesale; profile stores wear the
  seat's own settings (hat ON, guided false), so every helper-guard
  keeps holding in any seat. The sitting survives relaunch
  (profiles/sitting.txt) and reopens before sync starts serving.
- **Silk migration**: a pre-profile Care store (one person merged into
  root) becomes the first named door BY ITSELF at launch — data, trust
  and audio move behind the door, named from the person; the root store
  keeps only the seat's settings. Once, idempotent.
- **The loop stays perfect**: receive-first per profile. A PULL from a
  person whose door is closed gets SILENCE, never REVOKED (the severing
  word is only valid from the store that holds the trust — the
  wiped-pairings class of accident cannot recur across profiles). A
  PUSH for a closed door is decrypted with THAT profile's own key and
  waits in `profiles/<id>/inbox/`, merging the moment the door opens.
  Their key cannot open anyone else's door.
- test/care_profiles_test.dart (doors, sitting, relaunch, migration,
  cross-door trust, inbox).

Wave 2 (with BNS Care, main_care.dart): live serving for CLOSED doors
straight off their store files, and the ward view. Riding along in this
commit from the Prototyper's hands: the same-Mac discovery fix (TCP WHO
knock + NSBonjourServices consent keys) — see testing-live.md.

New caregiver report (docs/user-reports/caregiver-problems.md) still
open after this wave: L3's second Done ask + wrong-goal hero confirm,
Care later-today door, the honest paired-but-quiet banner, FAB on the
list. Next iterate per the caregiver's own order.

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

**Harness rebuilt + rehomed (2026-08-17, owner: "focus our files into
bns folder not gbns").** `.l4-test/` and `.l3-test/` moved from the
grokBNS folder into the bns repo root (gitignored — real stores and
ad-hoc app copies never enter git). All four bundles rebuilt from the
wall build (4b7987e): same bundle ids, same stores, container pointers
and entitlement paths updated to the new home. LIVE-VERIFIED on the L4
pair, one auto-sync round: Care's store healed `guidedMode true→false`
at load (the jailed-helper contamination is gone from disk), the
person's cage stayed `true` through the round (hats-never-travel held),
and the person's trusted row learned `peerIsHelper: true` from Care's
first PULL2 — every next send to Care is the care window. Pairing
survived the move untouched. The level-1 note also moved into this
folder (2026-08-17-level1problems.md); PROTOTYPER.md stays with the
fork it steers.

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
- **dayStartHour picker is on Sync** (not הגדרות): «מתי היום שלך מתחיל?».
  15 survives save+reload and a Care merge; a helper 0 cannot midnight
  a set start. Rebuild isolated L2 to see it.
- Windows person build shares the live Mac Documents store; Windows
  rebuild broken (MSBuild VCTargetsPath / ARM64). Alpha-env only.
- Ctrl+R once landed on /sync — unreproduced.

## Three-days pass (owner as user, 2026-08-18)

"I can go to the days before and insert useless information... the plan
for tomorrow should have its own screen showing the next day's plan
including addons... a proper dropdown instead of showing all hours the
day have including the past." Calendar-integrity work — inside the L1
stabilization queue, not new sync scope (that stays frozen).

- **The past is written** — `alreadyWritten` joined owl time (person's
  clock: at 02:00 with border 04:00, yesterday's date is still this
  day). The day view's plan door exists only on days still coming; a
  past day shows «יום שעבר נשאר כמו שהיה.» instead of a silently
  missing button. `_addEvent` guards for every hat. The three-days law:
  past = memory (look, remember), today = workbench (✓, skip, add,
  hours from now), future = plan room (add, build bags — the ✓ waits).
- **Tomorrow is one entity in its own room** — `/tomorrow`
  (TomorrowScreen): the next person-day woven into ONE list in owl
  order (02:00 night things close the list, timeless rows last),
  routines wearing their steps right on the tile ("stick to their
  entity with the steps to achieve things"), add-ons at their chosen
  hour with gather bags built tonight. Add door (fusion sheet, mic on
  the title), «להסיר» with a put-back snackbar (accept-less, his "done
  with thinking" temper), pinned «חזרה». Doors: Today's tomorrow door
  now routes here (was a raw push to the generic day view — now guided
  containment holds it), and Care's sitting home got «התוכנית למחר»
  beside «השעון שלהם» — the helper builds the next day from the seat,
  the ✓ stays the person's. Guided sees a window, not a workbench.
- **No wall of hours, no gone hours** — the fusion sheet learned
  `minHour`: hours that passed are simply not on the rail, ±15 clamps
  at the floor (and no longer wraps past midnight). Both plan doors
  (Today's «תוכנית להיום», day view's add) now open the fusion sheet
  floored at NOW with the next quarter preselected; the Material
  all-hours clock is gone from planning. `deleteEvent` joined the store
  (same merge caveat as deleteRoutine: no tombstones — a paired peer
  can resurrect; sync-wave item, frozen with the rest).

Tests 287 (+7: owl past-day, fusion floor, day-view three-days,
tomorrow-room weave + guided window). L1 queue continues: reach on
Today, miss-door count, hero confirm, FAB seat.

## Wake pass (owner as user, 2026-08-18 — "I don't get the notifications, I need an alarm clock")

Two findings in one report. Both owned:

- **Why notifications never arrived**: every reminder was scheduled
  `inexactAllowWhileIdle` — Samsung batches, defers, and swallows
  inexact alarms. Reminders now ride `exactAllowWhileIdle` with a
  silent inexact fallback, and the manifest carries `USE_EXACT_ALARM`
  (granted at install — BNS is an alarm-and-calendar app in the most
  literal sense), `SCHEDULE_EXACT_ALARM` (≤32), `USE_FULL_SCREEN_INTENT`,
  `SET_ALARM`, plus clock-app `queries` visibility.
- **The wake alarm — in-app or OS? BOTH, each doing what only it can.**
  BNS's own wake (`bns_wake` channel): a REAL alarm — importance max,
  alarm category + alarm audio stream, full-screen, FLAG_INSISTENT (the
  ring holds until answered), `AndroidScheduleMode.alarmClock` (Doze-
  immune, status-bar alarm icon), daily repeat. Its body is THE REASON
  (owner: "many days have nothing to wake up for and I do have"):
  `wakeBodyFor` — the day's first three things in owl order (02:00
  night pills never lead the morning), rebuilt fresh every reschedule;
  an empty day still says «היום שלך מחכה לך.» The phone's own clock is
  the second layer: «לשתול גם בשעון של הטלפון» (MainActivity
  `bns/wake_clock` channel, ACTION_SET_ALARM pre-filled with time +
  reason as the label, UI shown ON PURPOSE — the person sees it land
  and picks their SONG right there; Samsung's song/Spotify alarms are
  the customization he asked for, no bundled-audio scope). A clock
  alarm survives force-stop; ours carries the meaning.
- Seat + level rules: `_scheduleWake` refuses `caregiverDevice` (a
  sitting store's wake must ring on the person's nightstand, never the
  helper's); the wake section in the Tomorrow room hides on Care seats
  and in guided mode. Caregiver-set wake via sync = wave 2, frozen
  with the rest.
- `wakeAlarmTime`/`wakeAlarmNote` joined settings ('' = off; old files
  simply have no wake). Version-skew caveat applies as recorded.
- **Version answered** (owner asked mid-wave): we are at **0.12.0+4**
  (pubspec `version:`), scheme `0.MINOR.PATCH+build` — MINOR per
  feature wave, PATCH for fix-only, `+N` is the Android versionCode
  and climbs every shipped build. Apple/dist names derive from pubspec
  via build-apple.sh. 1.0.0 = the L1 day runs clean + distribution
  signing done.

Tests 293 (+6: settings round-trip incl. pre-wake files, wake words ×3,
tomorrow-room wake set flow, Care-seat refusal). Not yet lived-tested:
the actual ring on the S23 (needs a set wake + a morning).

### Versioning correction (owner, same day): the alpha law

"We neglect the versioning, it's +0.01 and an `a` at the end as this is
considered ALPHA." He is right — the tree already said 0.12a in three
hardcoded spots (about dialog, both export stamps) while pubspec and
dist names ignored it. Now ONE law: human version **0.12a** lives in
`lib/core/version.dart` (`kBnsVersion`); menu footer shows it (testers
report against that line); about + export stamps read it; build-apple
derives dist names from pubspec wearing the `a`;
`test/version_law_test.dart` welds constant↔pubspec so drift goes red.
Full scheme in docs/versioning.md: +0.01 per wave, `+N` versionCode
ever-climbing, the `a` falls only at 1.0. Tests 295.

### Wake door pass (owner, 2026-08-19 morning): "we didn't update the phone... its own button"

Two truths in one line. (1) The wake was buried — only reachable at the
bottom of the Tomorrow room; a feature you cannot find IS "not updated".
It now has its own door: «השכמה» in the menu map → /wake room (WakeScreen),
and the Tomorrow-room seat stays. One implementation (WakeControls) in
both doors so they can never drift; on a Care seat the room says where
the wake lives («ההשכמה גרה אצלם») instead of hiding. (2) Deploy proof
tightened: adb "Success" is claim, not proof — from now the loop verifies
`dumpsys package | versionName` on-device and the person-visible check is
the menu footer version line. v0.13a (+0.01 by the alpha law). Tests 298
(+3: wake room person/seat, menu door).

## Alarm-page pass (owner as user, 2026-08-19 — "I love it" + four cuts)

The clock plant is loved ("working awesome") — and the same report cut
four wounds. All owned:

- **Recording started TTS/listening uninvited** — after a take with no
  readable words, the capture screen auto-opened the system speech
  sheet ("the Waze door opens on its own"). Gone: nothing speaks or
  listens unless its worded button is pressed.
- **«עוד היום» was still a wall of numbers** — the last chip-wall in
  the app. LaterTodayDoor now opens the fusion sheet, floored at the
  tap's NOW. laterTodaySlots stays as a pure helper for ranking tests.
- **A moved time didn't move the tile** — _postponeItem wrote the store
  but left routinesProvider stale (the 400ms revision debounce raced
  the rebuild). It now invalidates in the same breath; and the
  "open from earlier" counter reads timeOn(todayKey), not the usual
  clock, so an 18:00-moved thing stops counting as an earlier miss.
- **THE ALARM PAGE** («שעון מעורר», the menu door): the wake on top;
  under it "מה נשאר היום" — the unanswered missions in person-day
  order (his lived ask: "all I wanted is to check what left in my
  day"); tap a mission → פעם אחת / כל יום / בימים מסוימים → the
  phone's clock opens pre-filled (EXTRA_DAYS rides the intent) — his
  "breach to OS, to make things tick"; plus «צלצול חופשי» from the
  hip. The nudges wear the person's own hand — "if I shall put alarms
  on the phone to annoy me to do stuff I would find it like caregiver
  is". Level 1–2 self-serve; guided/Care-seat see none of it.

**L3–4 over LAN — the owner asked "find if it can go off like this":
finding.** The alarm CONFIG can ride sync today (wakeAlarmTime already
lives in settings; mission-alarms would ride the same way) — but the
OS-clock PLANT cannot happen silently on receive: Android forbids
background activity launches, and ACTION_SET_ALARM is an activity.
What CAN go off: (a) BNS's own alarm layer (alarmClock-mode, Doze-
immune) fires from a sync-received config with no user action — that
part works headless; (b) the OS-clock plant lands on the person's NEXT
app-open ("ההשכמה שהמלווה קבע — לשתול בשעון?") — one worded tap, or
auto with SKIP_UI at open. So: caregiver sets → person's BNS rings
regardless; the phone-clock copy needs one open. Buildable when the
sync freeze lifts; recorded here as the design.

v0.14a. Tests 315 (+ alarm-page missions list; menu door renamed).
Not yet lived: the repeat-days plant on Samsung Clock.

## Ring-stop pass (owner, 2026-08-19 evening — "no way to shut down the alarm")

The clock plant with repeat days WORKED on Samsung ("the OS did kick
which is amazing, also mac and android wonderful") — and BNS's own
insistent ring had no off switch: FLAG_INSISTENT loops until the
notification dies, and nothing killed it. "It suppose to be an alarm
that you set off, a pop up screen, no other screen than accept or
snooze, thats it." Built exactly that:

- **The ring popup** (`/awake`, WakeRingScreen, NOT shell-wrapped):
  opening it silences the loop instantly (stopWakeRing = cancel + re-arm
  tomorrow) and shows ONE screen — big clock, the reason, «קמתי ✓» and
  «עוד 10 דקות». No bar, no menu, no list. Back answers like קמתי.
- **Two answers ride the notification itself** (wake_up / wake_snooze
  actions) and the plain tap routes payload 'wake' → /awake.
- **Snooze survives the machinery**: _wakeSnoozeUntil rides in memory;
  _scheduleWake schedules the one return ring instead of the daily while
  it is live (a foreground rescheduleAll cannot wipe it), then the daily
  resumes by itself.

**The Prototyper's "alarm for everyone" drop — taken on owner's word
("use the pr made for you") and on merit.** care_alarm.dart
(wakeAdoptChoice: a helper's wake reaches L3–4 always; L1–2 only onto
an EMPTY nightstand — they own their set wake; helper's empty never
wipes), Care-home alarm door (one ring per seat, the helper's pocket
stays quiet), pushTrustedNow (the set wake travels immediately),
fingerprint carries wake fields. This is the L3–4-over-LAN design from
yesterday's finding, built. Also merged: the L2 day-start PR (dressed
harness apps pin their sibling person/ store; Today paints the clock
door from the first settings read). Stray :TEMPkos files removed.

v0.15a. Tests 339. Lived next: the ring → popup → snooze loop on the S23.

**Lived, 2026-08-19 (owner, on the S23): the ring popup WORKED — snooze
too.** Fire → popup → עוד 10 דקות → return ring → קמתי, end to end.
The alarm story is closed as a person feature. Still unlived: the Care
seat's צלצול לכולם landing on a person's device over LAN.

## LAN-carry pass (owner: "lets test the care alarm on the lan pair", 2026-08-19)

Driven live on the L3 pair (this Mac, both harness apps, real UDP/TCP).
Result: **צלצול לכולם carried end to end** — Care set 21:15 + «כוס מים»
→ person store adopted (fullCare) → the person's שעון מעורר shows
«השכמה — 21:15, כל יום». Evidence: hunt-shots/lan-alarm-*.png.

Two finds on the way, both fixed before the pass went green:

- **The receive-first leg ate the instruction** (the owner saw it live:
  "the set time did not change according to your press... all the times
  around were not wired"). `pushTrustedNow` ran a full round; the pull
  leg brought the person's old 19:54 onto the seat BEFORE the send leg
  ran — the fresh 21:15 died on its own doorstep, and the person then
  received their own old time back. Fix: **hand-delivery** —
  `syncWithPeer(pushOnly: true)` skips the pull for instruction-sends;
  every adopt rule still runs on the receiving side, so no wall is
  bypassed. Wired into צלצול לכולם and «השעון שלהם» (same eater).
- **Copy polish** (owner: "official but not Karen... this is gibberish"):
  the alarm surfaces dropped the chatty filler — «נקבע כאן ומצלצל
  במכשיר שלהם. המכשיר הזה נשאר שקט», «טקסט שיוצג בצלצול (רשות)»,
  «אצל מי יצלצל», seat lines «כרגע X. ברמות 1–2 ההגדרה שלהם קודמת»,
  wake-room intro tightened. A full-app Hebrew copy audit with the
  owner joins the L1 queue.

Leftover (cosmetic): the wake preview line shows the day's opening even
when a note will replace it in the actual ring. Machine 0.15.1+8
(human 0.15a). Tests 339.

## Quiet-Today pass (owner: "lets get the level 1 today screen fixed, its crumbed out", 2026-08-19)

The founding complaint (2026-08-19 morning): "I am seeing all the daily
on my phone so crumbed out... I cannot tell what is next is what
isn't... all I wanted is to check what left in my day it attacked me
with confusing information." The anatomy showed the day painted THREE
times (hero + ComingUp strip + full heavy tiles) under six pieces of
chrome, with a FAB floating on top. Rebuilt for levels 1–2; guided
(L4) keeps its own tuned flow untouched:

- **No pep talk above the work** — «היום שלך.» + subtitle gone; the
  mad banner appears only while mad mode is ON; the vent chip stands
  alone, small (vents stay sacred and one tap away).
- **The chrome moved down**: sync line + the SET day-start door live in
  a quiet footer under the day (the L2 "too small to use" fix holds —
  the door is still big and worded, it just stopped standing between
  the person and their list). An UNSET day-start still stands on top —
  a question that needs answering may interrupt.
- **The day appears once**: ComingUp strip deleted; the hero is the one
  spotlight; below it «הרשימה של היום» with «N נשארו» — his "what
  left" as a number, always on.
- **DayQuietRow** (levels 1–2): one line per thing — clock, name,
  state. Tap = quiet ✓; pencil = the one miss door (gone once
  answered); long-press = עוד היום (fusion, floored at now);
  backpack only when the plan has a bag; «חלק 2 מתוך 3» only while
  mid-steps. Steps advance on the hero; kept words live in מילות
  היום; skip reasons one door away. THE DAY STAYS STEADY: answered
  rows dim IN PLACE.
- **FAB removed** for 1–2 (it sat on the list and duplicated the
  hero's ✓); guided keeps it — level 4 leans on the one big answer.

Evidence: hunt-shots/today-quiet-*.png (lived on the L3 person
harness). v0.16a. Tests 343 (+4 quiet-row).
Next in the L1 queue: the four-door miss sheet count, hero wrong-goal
confirm, and the full Hebrew copy audit.

## The ear that belongs to us (owner: "we need to make the recorder work in order to use my vision of pressing one button", 2026-08-19)

The vision, in his words: "pressing one button and using sst and record the
man, or we find a way to sst less fragile than android simple one that
cancel itself when you press any point of the screen... Or pure custom:
record package + any Whisper package."

Both halves were built, because they are one thing:

- **One microphone, named** (`VoiceTake`). The capture room owned an
  `AudioRecorder`, and every text field's mic opened a second listener
  through someone else's popup. Two recorders on one phone is not a
  feature, it is a silence — the second one fails and the person only
  learns that the button did nothing. Now every take in the app runs
  through one recorder that knows who is holding it.
- **The field mic stopped being a popup** (`DictationMicButton`, rewritten).
  It no longer opens Google's listening screen and no longer runs a live
  engine that gives up after a pause. Press once → it RECORDS. Press again
  → it reads the words off the finished file. A finger landing anywhere,
  a scroll, the keyboard, a notification: none of them can cancel a take
  any more. The cost is honest and shown: the words arrive a moment after
  the second press, and the button says «כותבים…» while the ear reads.
- **One ear for the whole app** (`Ear`). The ladder that lived inside the
  capture screen now serves every room: the offline ear first when it is
  installed, then the phone's own file ear (Google on Android 13+, Apple
  on iOS/macOS), then the desktop doors that came before.
- **The ear inside** (`WhisperEar`, whisper_ggml 2.6.0 — whisper.cpp
  compiled INTO the app, MIT). One 190 MB model download in Settings, and
  then Android, iOS, macOS, Windows and Linux all hear the same way, with
  no network, no account, and nobody else in the middle. Every borrowed
  ear fails somewhere — Google's needs Android 13 and a willing service,
  Apple's is Apple's, Windows has none — this one is just a file on the
  device.

**The build find (Gradle):** whisper_ggml's own library module aims at
compileSdk 34 while the ffmpeg it carries demands 35+, so the APK died
inside someone else's package. `android/build.gradle.kts` now raises every
library module that aims below 36 — by reflection, so an AGP major cannot
break it, and on the spot rather than in `afterEvaluate`, because the
`evaluationDependsOn(":app")` block above it has already forced evaluation.

Verified here: macOS debug app builds, Android APK builds, analyzer clean,
tests 354 (+6: the ear's language, the one microphone).

**LIVED ON THE S23 the same night** (the owner plugged the phone in
mid-pass — cable and wireless debugging both). The ear inside heard
Hebrew, on this phone, with nothing else involved:

- «אני צריך לזכור לקחת את התרופה בשמונה בערב, ולהתקשר לאמא.» — spoken
  by the Mac across the room into the phone's own microphone, written
  back WORD FOR WORD, punctuation and all (hunt-shots/ear-inside-heard.png).
  A longer sentence came back with three words bent out of eleven; a
  human speaking into their own phone has none of that distance.
- **The finger no longer kills the take** (hunt-shots/ear-inside-keyboard-survives.png):
  mid-dictation the screen was tapped, the field took focus and the
  KEYBOARD opened over half the room — «23ש» kept counting, and the
  words landed when the stop was pressed. That is the whole complaint,
  answered.
- **Timing, honestly**: an 8-second take became words about 16 seconds
  after the stop-press (first read of the run — the model load is inside
  that). The voice is kept instantly and «כותבים את המילים…» stands
  where the words will be, so the wait is visible, never a blank.
- **The model was quantized, and that is why it fits**: `small` q5_1 is
  190 MB instead of 488 MB, the same weights through the same code.

**Two finds, both fixed before the pass closed:**

- **The crumb it leaves.** To read an m4a, the plugin's ffmpeg writes
  `<take>.m4a.wav` next to the take — five times its size — and never
  cleans up. That folder is the person's kept VOICE; it is packed into
  .bns files and carried over sync. `WhisperEar` deletes the crumb in a
  `finally`, lived and confirmed on the phone.
- **The loop on a quiet take.** Fed a 23-second dictation that was
  mostly silence with a faint distant voice in it, whisper fed its own
  last guess back in and looped: «קצת רגלת כתובילים תודה רגלת
  כתובילים». `noContext: true` judges each window on its own audio; the
  next dictation of a normal sentence came back right
  (hunt-shots/ear-inside-field-dictation.png).

**The weight it brought.** whisper.cpp plus an ffmpeg per architecture
took the release APK from 63 MB to 134 MB. Ship builds now drop the
emulator architectures at packaging time (`lib/x86*`), which brings it
to 92 MB; debug builds keep every ABI. The 190 MB model is a separate,
deliberate download that only exists if the person asks for it.

Still unlived: the in-app download door over a real network (the model
was side-loaded onto the phone for this pass), and iOS/Windows/Linux.

## Pile pass (owner: "we Still sitting from last night", 2026-08-19 night)

The named pile, item by item:

- **The ear inside SHIPPED as 0.17a** (was sitting uncommitted): whisper.cpp
  in the app (`WhisperEar`), one ladder (`Ear`), one mic (`VoiceTake`), the
  field mic that survives a finger, the settings door «אוזן משלנו — עובדת
  בלי רשת» (~490 MB once). Machine 0.17.0+10 by the alpha law.
- **skip-why that can go blank — found and closed.** The new ear writes
  words AFTER the stop-press, so «זה לא קרה היום» pressed mid-take
  cancelled the spoken why (deleted it!), and pressed during «כותבים…»
  outran the words: a wordless skip nobody chose. Every worded keeper now
  settles the mic first (miss sheet both doors, diary keep, capture Save,
  plan ask) — one press finishes the take, waits for the words, then
  answers. The wordless-on-purpose skip stays a right: day view still says
  «לא קרה — לא נשמרה סיבה».
- **Eagered's naked calendar + — closed.** The + opens the day's ONE add
  ask (name EMPTY + mic + autofocus, «הוספה» asleep till a name exists,
  ביטול creates nothing). The «פגישה» prefill died with it. No more 03:07
  ghosts. test/named_plan_test.dart (+3).
- **Eagered's capture maze — already built, needs living**: forDate +
  «להוסיף רעיון ליום הזה» landed in 413dd6b; his last look was a 0.11
  build. Re-live on 0.17a.
- **The L2 window — seated.** gBNS LAUNCH.sh now places Person LEFT /
  Care RIGHT, both raised, person frontmost (lived: seating shot shows
  «היום מתחיל 15:00» on the person's own window). The seating CAUGHT a
  stale seat: BNS-Care.app predated the data-dir pin and asked the person
  question from bundle documents — deploy-all.sh now re-dresses the gBNS
  L2 pair every wave, so no harness app ages out of the truth again.
- **Capture still feels far — reframed, not yet closed.** On the phone
  bar «הקלטה» is one tap from Today; the room has ONE pinned Save since
  the one-save pass. The far-ness L2 lived was mostly the invisible
  window (they wrote into the day because they could not reach their own
  screen). Re-test after the seating + fresh 0.17a pair; if it still
  feels far ON a visible window, that's the next design wound.
- **One Care, few people — stays REQUIRED, stays frozen** (owner law: do
  not start the switcher; sync frozen until L1 clean). Not touched.
- **The New Bot seat has a job**: COPY-AUDITOR.md at the repo root — the
  queued full-app Hebrew copy audit (find, never fix; one report at
  docs/user-reports/copy-audit-YYYY-MM-DD.md; owner walks the findings).

Tests 357 (+3 named-plan). L1 queue continues: four-door miss sheet
count, hero wrong-goal confirm — and the copy audit now has a seat.

### Wave proof (same night): 0.17a everywhere, and the pair lived

deploy-all.sh ran green: S23 **versionName=0.17.0 / versionCode=10**
(dumpsys, the law's proof — adb Success alone is claim), /Applications
replaced, L3/L4 harness re-dressed, and the NEW stage re-dressed the
gBNS L2 pair. Relaunched and seated: the person window wears the 0.17a
day (hero with «שינוי שעה», «8 נשארו»), and the Care window finally
wears its REAL face — «אנשים» sitting on רמה 2, «נשמע לאחרונה לפני 0
דקות», «השעון שלהם — היום מתחיל 15:00 · נגמר 05:00». Shot:
gBNS/.l2-test/l2-pair-after-017a.png.

One more trap welded on the way: after a re-dress, `open` re-FRONTED
the stale Care process (old binary, person face) instead of launching
the new one — LAUNCH.sh now kills the pair first; the launcher
launches THE BUILD. Leftover for Ben's sit-down: the fresh signature
re-asks macOS Local Network for BNS-L2 — the dialog waits on the
person window («Allow» is his to tap).

### STT everywhere + the patch (owner: "did we use sst like in android in all the applications?", answered 2026-08-21)

Audit: nine fields had no mouth — the ROUTINES EDITOR (title, description,
every step title/note), the capture context field, both search boxes, the
sync share-name/device-name dialogs. All wear DictationMicButton now,
saves settle the mic first; passwords, the pairing code and the two
typed-confirmation gates stay typed on purpose (c64a7bb). The other seat's
queue fix rode along (7d969e8: takes queue inside Ear, the mic never
freezes when you speak twice; «עוד כותבים את המילים הקודמות»; AGENTS.md
gains THE EAR IS OURS / no censor). Fix-only on a shipped wave →
**0.17.1+11** (human 0.17a). Tests 362.

Deploy proof, honest: Mac side green (/Applications, L3/L4 harness, gBNS
L2 pair re-dressed; pair relaunched fresh — new PIDs, the launcher's
kill-first works). **S23 NOT installed — the phone was unplugged when the
build landed** (deploy-all said so; adb devices empty). The APK waits at
dist/BNS-android-v0.17a.apk (built from 0.17.1+11); one `adb install -r`
with the cable in, then dumpsys must say versionCode=11.

**Phone proof landed (2026-08-21, cable in):** `adb install -r` Success →
dumpsys **versionName=0.17.1 / versionCode=11** on the S23, data kept. The
nine mouths and the take-queue are in the owner's hand. Next lived:
speak a routine's name in the editor; speak twice fast in capture and
watch «עוד כותבים את המילים הקודמות» instead of a frozen mic.

## Wake-anchored day (owner, 2026-08-21: "push the entity of the routine into whatever hour the user woke up")

Built as 0.18a: the routine is a SHAPE whose head (first routine in owl
order) slides to the real wake; every routine of today follows by its own
gap, today only, via timeByDay (the שינוי שעה machinery — list/הבא/
reminders/day view/Care all follow). Plans stay on the clock, answered rows
stay, the person's own moves today win, quarter hours, nothing past the
border. One קמתי per day (settings.wokeAt) from three doors: the ring
popup, the shade's קמתי ✓, and the Today door «היום מתחיל ב-XX — קמתי /
עוד לא קמתי». Not built on purpose: "exit the app" on עוד לא קמתי (the
door just hushes until the next open); a time picker for "I actually woke
earlier" (a wall — the ring's קמתי already anchors at the alarm, and
שינוי שעה corrects a single row).
