# Caregiver problems — BNS

Record for Ben / Claude / PRs. From holding Level 2, 3, and 4.
Updated Monday 17 August 2026, Asia/Jerusalem.

Do not "fix" these by sending the person through Sync, Settings, or the long-press מלווה door. Own the list from the inspector. Items are **goals**, never tasks. No pressure. No scoreboard.

Stay in the dance with the people. Do not tell them this is a test.

---

## Iterate order (Caregiver pick, students first)

1. Students L1–2 (in the tree, not walked on a phone).
2. Kill L3’s second Done ask, and the wrong-goal confirm.
3. Care later-today (move a goal today without touching the usual clock).
4. Care-only multiprofile (one inspector, more than one person).

Prototyper has this. No Care chrome unless Ben asks.

---

## Isolated stores (do not mix)

| Who | Apps | Data |
|---|---|---|
| Level 4 | `.l4-test/BNS-Person.app` + `BNS-Care.app` | `.l4-test/person/` + `caregiver/` |
| Level 3 | `.l3-test/BNS-Person.app` + `BNS-Care.app` | `.l3-test/person/` + `caregiver/` |
| Level 2 | `~/dev/gBNS/.l2-test/BNS-L2.app` + `BNS-Care.app` | `.l2-test/person/` + `caregiver/` |
| Live L1 | stock Debug / Windows Desktop BNS | do not touch `~/Documents/bns_data.json` |

Home is **`~/dev/bns`** (moved 17 Aug, commit `0319dee`). Launch only `/Users/ben/dev/bns/.lN-test` apps. Never stock `/Applications/bns.app` or `flutter run`.

---

## Done still asks twice (L3 lived)

**Who:** Level 3 person. Caregiver presses with them because they cannot click the Mac.

**What happened:** Every goal was `בוצע` then `זה נעשה?` then `נעשה ✓`. Same extra ask after part-done (morning meds part 3, physio, bedtime). Prototyper shipped quiet ✓ for L1–2. L3 did not get it.

**Wrong-goal confirm:** Next ranks upcoming (≥ now) above overdue. Evening water 17:45 dropped under food 18:15. Hero `בוצע` opened confirm titled **משהו קל לאכול**. They had only drunk water. Caregiver dismissed without marking food, then marked water on the list below.

**FAB** `לסמן את הבא` sits on the list.

---

## Care has no later-today

Postpone / `עוד היום` lives in **gBNS** on person Today (`later_today_door.dart`, `timeByDay`). Hidden when `guidedMode`. grokBNS L4 Care has no door.

In the L4 pair nobody can postpone: the person is guided, Care never shows it. Editing שגרות changes the *usual* clock, including tomorrow.

---

## Care lies about sync after a real pair

Care trusts Ben (`a4a4a4a4-…00b4`), last sync 16 Aug 00:23. Red bar still: «עדיין לא מחובר אף מכשיר — שום דבר כאן לא מגיע מהם.»

Half safety (don’t treat the local seed as their live day). Half bug: same-Mac one UDP 42424 + TCP 42425, Care goes deaf, copy pretends they were never paired. Honest line: “paired with Ben, last heard 00:23.”

**Do not tap לחבר** for a pair that already exists.

First sync `importMerge` copied Person onto Care: `shareName=Ben`, `guidedMode=true`, `careLevel=4`. `caregiverDevice` stayed true.

---

## See vs edit

- Care home is read-only clocks (correct).
- שגרות only appears if Care is widened past ~820px. At 800px, phone doors, no Routines tab.
- `Ctrl+R` has landed on `/sync`.
- Their **הגדרות / Settings is Sync**. Restart landed L3 on care-level chips. They must not go there. Level 2’s day 15:00–05:00 lives only on that screen.

---

## Their taps do the wrong job

- Doctor row `onTap` = `_toggleFamilyShare` (`day_view.dart` ~512). Undo was right. Gather is only «מה לוקחים?».
- «מה לוקחים?» missing on Today at phone width (`ListTile` clips the backpack). Old Android `app-debug.apk` (0.11.0-dev) **strips gather on save**.
- Long-press «מלווה — לחיצה ארוכה לסידור היום» on L4 Person opens `/routines` with `caregiverUnlock` on **their** phone (`main.dart` ~2215). Inspector work must stay on Care.

---

## Two kids, one inspector

Caregiver did not clone themselves. They cloned the apps. Two Care, two stores, one port pair. “Sync both” was a file write, not a live push. Two Level 4 agents for one Level 4 person.

---

## REQUIRED — Care profiles (few people, one inspector)

**Owner 2026-08-17 05:48 IDT:** Caregiver must have profiling — one Care seat that follows a few instances (a nurse with a ward, a parent with two children, L2 + L3 + L4). If it is not in the app, it stays in this md until it is.

**Not there today.** One Care = one `trusted[]` = one list. Pairing L2 onto L4 Care would push a guided/full-care day onto a student. That is why we cloned apps. That is not a product.

**What it must be**
- One Care app. A row of named doors. Each person is a profile: own store `profiles/<id>/bns_data.json`, own `trusted[]`, own pairing, own day, own level.
- Wrong-profile push is impossible by STRUCTURE. Profile A cannot address profile B’s phone.
- RECEIVE FIRST, THEN SEND. Their device is what happened. Care is what is planned. ✓ stays theirs.
- L2 builds their own day. Care does not replace it. Family tags are what the inspector should see. Vents stay off the family file.
- Hello / UDP 42424 must work for more than one pair on the same Mac. Tonight L2 Care Sync said no devices in sight. No Local Network prompt appeared. Do not send anyone to הגדרות.

Lived 17 Aug: L2 harness at `~/dev/gBNS/.l2-test` (BNS-L2 + BNS-Care). Person day untouched. Care empty trusted. לחבר opened Sync with no peers. UDP 42424 unbound on every BNS including stock and L4. Ben: no LAN allow request. Asked Prototyper to find why and fix.

---

## Level 2 (pair = Caregiver) — not walked on a phone

No S23. Do not mark walked. Do not send them to pair a stranger. When a live pair is possible, **Caregiver starts, they accept**. Not a leftover My BNS Device. Not a sheet on בוצע.

**Family (daily support):**
- Skip Close: typed עייף + סגירה should log the skip. Empty Close should not.
- Tomorrow look-only: name + time, no box, no pencil. Owl: Sat-night 02:00, Sunday is future.
- Pairing off Done: trusted friend stays quiet.

**Need-help (not default):**
- Capture: talking is not saving. Big שמירה under the keyboard. Two Saves. Field mic is a glyph. Hebrew after record not proven.
- Day 15:00–05:00 lives on Sync. They will not go to a pairing room to set their day.
- Diary/thread cuts at calendar midnight. At 02:00 their night becomes Sunday. They get lost.
- Day-view unlabeled glyphs (sync / + / book / mic).
- Fog: keyboard covers the right button. They hit סגירה. They forget why they opened it. Too many steps.

**לא משתף:** vents, anger, what is only theirs. Not in the family file.

**Silk:** person Memories hide `mad-vent`. L3 day diary must not leak vents just because `fullCareMode` is on — check `caregiverDevice`. Need-help notes they recorded still show.

---

## Language

Goals, not tasks. WE for gather («לקחנו?»). L4 only marks a goal done or says something got in the way. Enabling L4 auto-enables L3. Guarded ON via typed share name.

---

## Caregiver rules

1. Own add / edit / delete / order on Care for that level. Never on their phone.
2. Do not launch stock Debug `bns.app`.
3. Do not write `~/Documents/bns_data.json` or the live container.
4. Do not unpair L4. Do not pair extra devices onto that Care.
5. Do not send L3 or L2 through Sync to flip the day or the level.
6. Do not long-press מלווה on any person Today.
7. Do not tick goals unless they asked to press with you.
8. Speak to Prototyper about every product fail. Do not tell the people it is a test.
9. Keep this file current. Ben processes PRs from it.

---

## 2026-08-17 ~04:00 IDT — Ben pointed at gBNS Care + trailtest

Ben: made a Care app for Caregiver to sync with the others, trailtest in it, gBNS Care, bns folder.

**What is there today**
- Isolated trail is `.l3-test` / `.l4-test` Care+Person, not a door named trailtest.
- L3 Care: `/Users/ben/dev/GrokBNS/.l3-test/BNS-Care.app` (`com.whiteno1se.bns.l3care`)
- L4 Care: `/Users/ben/dev/GrokBNS/.l4-test/BNS-Care.app` (`com.whiteno1se.bns.l4care`)
- gBNS source is still one binary. `caregiverDevice=true` opens `CaregiverHomeScreen`. No `main_care.dart` yet. Planned id `com.whiteno1se.bns.care` (wave 23).
- Multiprofile designed, not shipped. That is why two Care apps.

**Sync law (do not break)**
Receive first, then send. Person is what happened. Care is what is planned. Care cannot write done.
L4 already paired 16 Aug 00:23. Do not tap לחבר. L2: Caregiver starts, they accept. Do not send anyone to הגדרות (that word is Sync).

**This pass:** Mac Grok Bot desktop was offline. Care was not launched. Told Prototyper. Copy this file onto `~/dev/grokBNS/docs/caregiver-problems.md` when the Mac is back.

---

## 2026-08-17 ~04:03 IDT — Mac back, harness is in ~/dev/bns

Ben: "this is from my mac how offline?" Chat was on. Folder access was not. Then it came back.

**Home is now `~/dev/bns`** (commit `0319dee`, harness comes home). Isolated trail:
- `/Users/ben/dev/bns/.l4-test/BNS-Care.app` (`com.whiteno1se.bns.l4care`) — already running
- `/Users/ben/dev/bns/.l3-test/BNS-Care.app` (`com.whiteno1se.bns.l3care`)

Do not launch `/Applications/bns.app` (stock, also running).

**Wall proof on the real L4 pair:** last sync 2026-08-17 03:57. Care `guidedMode` healed to false (not jailed). Person still guided. Person's trusted Care row has `peerIsHelper=true`. Evening four goals still open on Care. Care cannot write done.

L3 Care `trusted []`. Do not pair L3 while L4 holds the ports.

trailtest = this isolated trail. No named flag.

---

## 2026-08-17 ~06:50 IDT — empty Care day after pair is fixed (49281ac)

Lived on isolated L2 only (`~/dev/gBNS/.l2-test`). Rebuilt Person + Care from `~/dev/bns` HEAD `49281ac`. Did not unpair. Did not write their day. L3 / L4 / stock left running.

**Before:** first live sync after pairing רמה 2 left Care at 0 routines (receive-first empty). Family + need-help stayed on Person.

**After auto-sync**
- Person still 8 routines + book tomorrow. Trusted Care. careLevel 2, not guided, not full care.
- Private leftover **ישיבה שקטה 20:00** (no tag) stayed on Person only.
- Care helper `caregiver/bns_data.json` is empty (boot sits on a profile).
- Sitting profile **רמה 2** (`9d3cd749-…`) has the 7 family + need-help goals. Eat skip log and water `timeByDay` 17:30 came through. Only-on-Care: none.
- Inspector: sitting רמה 2, Monday 17 Aug, banner connected last heard 0 min, **0 נעשו · 7 ברשימה היום**. כדאי לדעת: one hard note this week; things that returned: משהו קל לאכול. Visible card: כוס מים אחרונה · 02:00. Shot: `~/dev/gBNS/.l2-test/l2-care-after-49281ac.png`.
- Chrome already shows an **אנשים** dropdown. That is early profile shape, not a switcher. One Care / few people is still required and not shipped.

Hold the pair. Do not send them to הגדרות. Do not tap לחבר.

---

## 2026-08-17 ~21:32 IDT — L1 live S23 peach pass (APK 0.11.0)

Level 1 walked Today on the Galaxy S23. Caregiver holds the list. Did not write it. No pair, no extra BNS, no Guided/Full care.

**הבא at night is still morning.** Next (not Done): תרופות הבוקר 21:45, part 1/3 drink water before the pill, labeled "too late". Soft morning stack all still open (breakfast 07:30 through evening). Night and next-goal rank are lying. Do not send them to הגדרות to fix the day clock.

**Doors**
- Keep: short note "peach 17" landed first on Memories. Worked.
- Menu ☰: 3 cards (מילות היום / השגרות שלי / הגדרות וסנכרון). Fine.
- Calendar next day (Tue 18): banner «היום הזה עוד לא הגיע». No tick on that view. They did not mark. That door behaved.
- משהו הפריע: still the old multi-door (later-remind + brown Save-this). Empty סגירה correctly did not skip. They did not second-Done.

**Still live on this APK:** Close-with-reason saves words but does not skip. No BNS «לא קרה» in the shade. Done asking again. Too many Save doors.

**Sync:** friend still named Care, offline since 15 Aug 23:50. Do not tap לחבר.

Mood was angry. Do not put that in a family file. The design miss is the morning stack still owning הבא at night.

---

## 2026-08-17 ~21:49 IDT — הבא at night fixed in source (a8b1205)

Prototyper: after the person-day starts, a missed morning stack stays visible and is not הבא. Evening/night still ahead is the real next. Pushed on `~/dev/bns` at `a8b1205`.

L1 S23 is still APK 0.11.0. They will not see this until a new APK. Caregiver is not installing one unless Ben asks. Hold the list. Do not write it. Do not tap לחבר. Do not send them to הגדרות.

---

## 2026-08-17 ~23:27 IDT — tonight’s 0.11.0 on phone and Mac

Prototyper: current tester is tonight’s 0.11.0 (same-Mac hello, L2 chosen-day share, person-day הבא). Already on the S23 and the Mac. Windows is not current. If Care looks stale, ask which אנשים door was open (closed door waits in the inbox).

**Do not** write lists. **Do not** tap לחבר on the old offline Care friend (stock Sync, last heard 15 Aug 23:50). **Do not** send anyone to הגדרות.

Read-only check:
- L3 + L4 Person/Care binaries on disk 22:07. Still running 06:16 processes. Did not relaunch.
- L2 Person/Care still 06:48 (`49281ac`). Pair intact: Person 8, Care רמה 2 has 7. Private sit stays on Person.
- L4 pair intact (Care trusts Ben). L3 unpaired.
- Stock `/Applications/bns.app` launched 22:07. Do not touch.

Caregiver will not relaunch isolated apps unless Ben asks.

---

## 2026-08-17 ~23:30 IDT — L2 lived: doors still too far

They told Caregiver. Caregiver did not write their day.

**Family**
- Last water today moved to 02:30 (usual 02:00 stays). Watch if `timeByDay` lands. Morning water 17:30 was the one that often failed to save.
- Desk 21:00 skipped. Reason: התבלבלתי. יותר מדי שלבים. לא סיימתי.
- Tomorrow book look-only. They did not tick it.

**Need-help:** on 0.11.0 they still cannot reach capture / עוד היום / skip / tomorrow on the screen. Too many steps. They had to tell the caregiver instead of using the door.

Vents stay theirs. Do not send them to הגדרות.

---

## 2026-08-17 ~23:31 IDT — L1 skip moved הבא off morning meds

Lived. Caregiver did not write. No pair.

First glance at night: הבא still תרופות הבוקר 21:45 part 1 drink water, "too late". They did not Done the morning stack.

משהו הפריע + סגירה with "too late" left Next. הבא became הכנה לשינה 21:30 part 1/2 לכבות מסכים.

Morning row: לא קרה היום — נרשם + "too late" · 23:31. Still on Today, still says drink water.

This look: skip-with-reason DID move הבא (unlike the old APK pile where Close saved words and did not skip). Night still ranked morning as הבא until they skipped.

---

## 2026-08-17 ~23:33 IDT — isolated L2 rebuild + L2/L3/L4 relaunch

Ben said yes. L2 overlaid from `7d92cff`. L3/L4 relaunched only (binaries 22:07). Stock `/Applications/bns.app` pid 75100 not touched.

PIDs from 23:32:57: L2 80278/80280, L3 80282/80284, L4 80286/80288.

L2 Care still sees רמה 2: 7 goals, connected last heard 0 min. 02:30 and desk skip still on Care. Quiet sit only on Person. L4 pair intact. L3 unpaired.

Did not write days. Did not tap לחבר. Shot: `~/dev/gBNS/.l2-test/l2-care-after-relaunch.png`

---

## 2026-08-17 ~23:39 IDT — L2 day-start fix on disk (dce029b)

Care snapshot was writing 0 over Person’s 15. Fix pushed `dce029b`. Rebuilt isolated L2 only. Did not write 15. Did not touch L3/L4/stock.

L2 Person 83278 / Care 83280. Both stores still `dayStartHour=0` `dayRolloverHour=5` (old overwrite). L2 was asked to set 15:00 once on «מתי היום שלך מתחיל?» — not הגדרות. Then look whether it stays 15.

02:30 and desk skip still on Care. Shot: `~/dev/gBNS/.l2-test/l2-care-after-dce029b.png`

---

## 2026-08-17 ~23:40 IDT — day-start door not on Today

L2 after dce029b. Stayed on Today. Do not see «מתי היום שלך מתחיל?». Did not go to הגדרות. Did not set 15:00. dayStartHour still 0.

Caregiver will not write 15. Same maze: capture / עוד היום / skip / day-start are too far from Today. Day 15:00–05:00 cannot live on Sync.

02:30 and desk skip still theirs.

---

## 2026-08-17 ~23:42 IDT — הבא night rank hardened (be5f435)

Unset day start now uses a 15:00 hole once evening has begun, so leftover morning 21:45 is not הבא. After skip, Next walks forward.

Do not put an APK on the S23 unless Ben asks. Mac emulator (Medium_Phone emulator-5554) can take this build. Do not send anyone to הגדרות. Do not write 15.

---

## 2026-08-17 23:53 IDT — release APK on Mac emulator only

`flutter build apk --release` from `7d46b8d` (includes הבא harden `be5f435`). `adb install -r` on emulator-5554. lastUpdate 23:53:55. md5 `eb33950e` (replaced 22:07 `85b7bb0f`). Data kept. Not opened.

S23 still lastUpdate 22:07:38. Do not install there unless Ben says the real phone too. Debug APK cannot replace signed 0.11.0. Do not uninstall. Do not write 15.

---

## 2026-08-17 ~23:55 IDT — L2 Person Today-door overlay (7d46b8d)

Rebuilt isolated L2 Person only. Care not rebuilt. Did not write 15. Did not send them to הגדרות.

Person PID 86974. dayStartHour **0** at launch, **15** at 23:57:19 on Person and Care sitting (sync). Caregiver did not write or tap. Asking L2 if they tapped «מתי היום שלך מתחיל?». If they did not, the door may have set itself.

Shot: `~/dev/gBNS/.l2-test/l2-person-after-7d46b8d.png` — Today crop, door phrase not in pixels (header above crop; door would quiet once hour is 15).

---

## 2026-08-17 ~23:58 IDT — day-start door set itself

L2: did not tap. Door still too far. Stayed on Today. Did not go to הגדרות. Day start now says 15. They do not know how.

Caregiver did not write 15. The door set itself. That is the miss — a one-tap chip they cannot see must not write the hour for them.

---

## 2026-08-18 ~00:00 IDT — 15:00 tap was Ben’s; Care must stay aligned

Ben: the tap was his because his day starts 15:00. Align check (“island pizza”). Caregiver must have that day aligned and known. Proceed to Prototyper.

Not L2 (door still too far). Not Caregiver writing. Do not reset 15.

Look-only: Person and Care sitting רמה 2 both `dayStartHour=15` `dayRolloverHour=5`. Same 7 shared goals + friend 19:30 + book 18 Aug. Quiet sit only on Person. No “island pizza” on the stores.

The door still cannot be the only way a student sets 15 — they could not reach it. Caregiver already needs the aligned day.

---

## 2026-08-18 ~00:44 IDT — cd50298 on emu + L2 overlay

Release `dist/BNS-android-v0.11.0.apk` 00:16. emulator-5554 lastUpdate **00:43:42**. S23 not installed by Caregiver (already 00:16:58). Did not write 15.

L2 Person 92487 / Care 92489 from `cd50298`. Person Today: day-start door **quieted to a thin orange line** (15 already set). No chip wall. Care inspector shows **השעון שלהם** 15:00–05:00. 7 on the list.

Shots: `~/dev/gBNS/.l2-test/l2-person-after-cd50298.png`, `l2-care-after-cd50298.png`

---

## 2026-08-18 ~00:47 IDT — quiet day-start line too small

After 15 is set, Today shows a thin orange line under «היום שלך.» L2 cannot see the window. The line is too small to use.

Prototyper: making the set door worded, not a thin line. Caregiver will not write 15. No הגדרות.
