# Caregiver problems — BNS

Problems the caregiver hit while carrying the bag for Level 3 and Level 4.
Sunday 16 August 2026, Asia/Jerusalem.

Do not "fix" these by sending the person through Sync, Settings, or the long-press מלווה door. Own the list from the inspector device.

Language: the items on the list are **goals**, never tasks. No pressure. No scoreboard.

---

## Isolated stores (do not mix)

| Who | Apps | Data | Status 16 Aug |
|---|---|---|---|
| Level 4 | `.l4-test/BNS-Person.app` + `BNS-Care.app` | `.l4-test/person/` + `caregiver/` | Paired 00:23 IDT. Leave it. |
| Level 3 | `.l3-test/BNS-Person.app` + `BNS-Care.app` | `.l3-test/person/` + `caregiver/` | Not paired. Levels already correct in JSON. |
| Live L1 | stock Debug `BNS.app` / Windows `Desktop\BNS\bns.exe` | container `com.whiteno1se.bns` and/or `~/Documents/bns_data.json` | Restored to Level 1 after a Windows seed wrote L4 into Documents. Do not touch. |

Launch only the matching `.lN-test/LAUNCH.sh` or that side's Care app. Never `flutter run -d macos` or Xcode Debug BNS for this work.

---

## Level 4 — long-press מלווה opens caregiver setup on the person device

**Who:** Level 4 person (guided, list only).

**What they were doing:** Today. The only legal moves are mark a goal done, or long-press a **goal** if something got in the way.

**What happened:** Long-press on «מלווה — לחיצה ארוכה לסידור היום» opens `/routines` with `caregiverUnlock: true` on the **person** device. Full add / edit / delete.

**Why this is bad:** Product law says the inspector builds everything. This door leaves CRUD on their phone. The person must not be asked to arrange the day.

**Do not use this door.** Own the list from Care (`BNS L4 Care` → שגרות / «לבנות את היום שלהם»).

**Where:** `lib/main.dart` ~2215. Visible on Mac L4 Person and on the Android debug seed.

---

## Level 4 — first sync copies the person's identity onto Care

**Who:** Caregiver on `BNS L4 Care`.

**What happened:** After the 00:23 pair (`importMerge`), Care's store became `shareName=Ben`, `guidedMode=true`, `careLevel=4`. `caregiverDevice` stayed true, so the inspector UI survived.

**Why this is bad:** Care now looks like the person in settings. A later relaunch or a Sync glance can confuse who is who. The person must stay Level 4; Care must stay the inspector.

**Pair that worked:** Care trusted Ben `a4a4a4a4-…00b4`; Person trusted Care `c4c4c4c4-…00c4`. LAN IP `192.168.31.241`. Code `993685` on Person's `EnterCodeDialog` (not the מלווה leak). UDP 42424 + TCP 42425 on the same Mac is fine when one side listens and the other connects to the Wi-Fi IP (not 127.0.0.1).

**After relaunch:** Person held both sockets. Care kept the stored pair but live auto-sync can sit idle until it sees Person again.

---

## Level 4 — Care phone-width hides Routines

**Who:** Caregiver on Mac Care.

**What happened:** At 800×700 Care uses phone doors (Today / לשמור / זיכרונות / לוח שנה). No שגרות tab. Sidebar «שגרות» only appears at width ≥ 820. `Ctrl+R` from home once landed on `/sync`.

**Why this is bad:** The inspector cannot build the day without widening the window or hitting the wrong door (Sync).

**Workaround:** Widen Care past 820px, then שגרות. Do not send the person to Sync.

---

## Level 3 — doctor row tap marks family share instead of opening the plan

**Who:** Level 3 person (full care, guided off). They still use Today, Keep this, Memories, Calendar, and they answer.

**What they were doing:** Open the doctor plan to see what we take.

**What happened:** Tap on the doctor row calls `_toggleFamilyShare`. Same as the family icon. They had to undo. Gather opens only from the backpack «מה לוקחים?».

**Why this is bad:** A normal tap shares a medical plan with family. The person thinks they broke it. The bag list never opens.

**Where:** `lib/features/calendar/day_view.dart` ~512.

**What to tell the person:** Do not tap the doctor row. Use the backpack. If the backpack is missing, that is the next bug — do not send them through Sync to hunt for it.

---

## Level 3 — «מה לוקחים?» is not a door they can use

**Who:** Level 3 person, 16 Aug ~03:29 IDT.

**What they were doing:** The day. They did not open Sync. They did not tap the doctor row.

**What happened:**
- Backpack «מה לוקחים?» is not on Today.
- Saturday 15 shows the doctor at 05:00 with "plan on the next card" and **only** the family-share icon. No next card. No gather list.
- Sunday 16 calendar is empty.

**Why this is bad:** Answering "did we take this?" is the Level 3 job. If the bag has no door, they cannot answer. Caregiver-owned gather in `.l3-test` JSON (מפתחות, טלפון, ניירות, מים on `qa-doctor-0500`) does not match what they are looking at — they still see Saturday 15 **without** gather. They are on a different store or a stale window.

**Found 16 Aug ~03:39 IDT:** They were on Android emulator `emulator-5554` / `com.whiteno1se.bns.debug` (AVD Medium_Phone, store says `BNS L4 Android Person`). That 0.11.0-dev APK (built 15 Aug) **does not include gather** and strips `gather` on save. Phone-width calendar also clips the ~48dp backpack under `ListTile(isThreeLine: true)`.

**The one control:** «מה לוקחים?» on the doctor plan in **Mac L3 Person** (Today → הצעדים הרכים, or a wide calendar day). Not the row. Not the family icon.

**Do not** rebuild/pair Android onto Mac Care. If that APK is opened again, gather will drop on the next save.

---

## Level 3 — restart / Settings lands on Sync and care levels

**Who:** Level 3 person.

**What happened:** After a restart they landed on Sync and care-level chips, not Today.

**Why this is bad:** They must not pair or change care level. That door is a burden. Cold start in code is `/` → Today when `caregiverDevice` is false. On the phone the top-bar word **הגדרות** pushes `/sync`, which is also the care-level card.

**Do not send them through Sync to "fix" the level.** Isolated L3 JSON is already `careLevel=3`, `fullCareMode=true`, `guidedMode=false`, `caregiverDevice=false`.

---

## Level 3 — "I'm mad" vents leak back in Memories / day diary

**Who:** Level 3 person.

**What they were doing:** Venting. Copy said only they see it.

**What happened:** Memories showed the rants back.

**Why this is bad:** A vent that comes back feels like the app told on them, or like the day is a scoreboard of anger.

**What the code does:**
- Real `mad-vent` tags: person Memories uses `includeMad: false` and should hide them. They burn out (~2 days).
- Caregiver home always `includeMadVents: true` (L3: rants are the signal for the helper).
- **Leak:** `DayThreadScreen` sets `includeMad = settings.fullCareMode || madActive` and does **not** check `caregiverDevice`. L3 person has `fullCareMode: true`, so the day diary shows vents on **their** device.
- Seed notes tagged `need-help` (not `mad-vent`) follow silk law — if they recorded it, they see it. Those are not vents.

**Caregiver view vs person view:** helper should see rants. Person Memories should not. Day diary currently fails that.

---

## Windows person shares the live Mac store

**Who:** Caregiver trying a Windows person (Parallels Windows 11).

**What happened:** `C:\Users\ben\Desktop\BNS\bns.exe` uses Shared Profile Documents = `~/Documents/bns_data.json`. Seeding L4 on Windows overwrote the **live** store (`deviceName=BNS L4 Win Person`, `guidedMode=true`, `careLevel=4`). Isolated L4 pair was not in that file.

**Why this is bad:** A test flip changes Ben's live Level 1 day.

**What we did:** Restored from `.l4-test/win-person-bns_data-before-l4.json` to Level 1 `My BNS Device`. Quit Windows `bns.exe`. File may still be owned by `root`.

**Do not pair Windows or the Android emulator to Mac L4 Care.** That can kick the existing pair. `--data-dir` is in `docs/testing-live.md` and is **not** in the Dart.

Windows source on the VM is `C:\Users\ben\dev\gBNS` (not `grokBNS`). Rebuild is broken (MSBuild `VCTargetsPath` / ARM64).

---

## Android emulator has no isolated L4/L3 person

**Who:** Caregiver.

**What happened:** `emulator-5554` (`Medium_Phone`) had no BNS APK. Stock `app-debug.apk` (`com.whiteno1se.bns.debug`) was installed and seeded as L4 Person with empty `trusted[]`. Physical S23 already has live `com.whiteno1se.bns` / `.debug` — leave it.

**Why this is bad:** Same applicationId as debug. No `.l4-test`-style isolate. Easy to pair into the Mac Care pair or the live phone.

**Held off on pairing.** Level 4 later said stop Windows/Android extra work.

---

## Caregiver rules (so we do not make these worse)

1. Own add / edit / delete / order on the **Care** app for that level. Never on the person phone.
2. Do not launch stock Debug `bns.app`.
3. Do not write `~/Documents/bns_data.json` or the live container.
4. Do not unpair L4. Do not pair extra devices onto that Care.
5. Do not send Level 3 through Sync to flip full care / guided / caregiver.
6. Do not long-press מלווה on any person Today.
7. Do not tick goals for the person. They mark done, or they say something got in the way.
8. Speak kindly. Goals, not tasks. WE for gather ("לקחנו?"), never a missing-count scoreboard.
