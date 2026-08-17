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
