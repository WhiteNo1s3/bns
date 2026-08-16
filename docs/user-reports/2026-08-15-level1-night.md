# User reports — BNS

Collected from live use. Saturday 15 August 2026, Asia/Jerusalem.

---

## Mac pairing window stays up after the device is already trusted

**Who:** Level 1 user (most braincells, still TBI/DAI). Mac + phone already wired.

**What they were doing:** Using BNS on the Mac. The phone is already a trusted device named **Ben Phon**. They were not trying to add a new device.

**What happened:** The Mac kept a pairing / connect window on the screen: *"My BNS Device" wants to connect* (Hebrew: `"My BNS Device" רוצה להתחבר`). It asked for a code and would not go away. The user canceled. After cancel, the trusted list was already set: **Ben Phon**, LAN allowed, auto-sync on. Last sync from earlier: 14 Aug 2026 17:59.

**Why this is bad:** The person thinks pairing failed, or that Ben Phon is a stranger. They get thrown into a code box they already finished. Cancel feels like they broke it. The window sits on Today and eats every tap — they cannot mark done or keep a thought until they cancel. The Mac treats a friend like a new device.

**What they said:** The Mac version is bugged with pairing. It keeps the window, and it was already paired. They canceled and it was already set as Ben Phon.

**Do not "fix" by pairing again.** Another pair makes the stuck window come back.

**Seen also (same evening, same machines):**
- Phone Sync showed **no** trusted devices while the Mac already listed Ben Phon.
- Phone discovered "Mac" and offered Pair even though the Mac already trusted that phone.
- A pairing sheet (code 306752) appeared on the phone by itself while the person was trying to mark a walk done.
- Mac UDP discovery (port 42424) was not listening; the connect box still appeared.

**Platforms:** macOS (live gBNS debug `bns.app`), Galaxy S23 Ultra (`com.whiteno1se.bns`). Same Wi-Fi.

---

## Phone new menu — 15 Aug 2026 ~23:17–23:34 IDT

**Who:** Level 1 live pass on Galaxy S23 Ultra after the new 7-card menu.

**Felt good**
- Named cards with a subtitle. Easier than icon-only tabs.
- Typed keep `menu test note` saved and showed up first on Memories.
- Evening meds Done eventually moved the day to sleep-prep.
- Miss copy is kind: "לא קרה? זה בסדר".
- Calendar jump to Sunday 16 works; that day's routines are readable.
- Adding a plan on tomorrow works (event appeared).
- Care still online, last sync 15 Aug 23:33. Hebrew keyboard this pass.

**Annoyed / broken**
- Cold start opens leftover Save-this, not the menu.
- ☰ has no label. Old 4-tab still there = two maps. Tab says Today while you are in Menu or Sync. Settings card clipped under the 4-tab until you scroll.
- Memories and "today's words" share the same book icon.
- Pep talk / welcome essay sits above the work.
- Three Dones: בוצע + FAB + "זה נעשה?" dialog. Done asks again.
- FAB covers "something interfered" and the Memories list.
- Keyboard hides the big Save; only the tiny header Save remains.
- Miss-reason save (`לשמור את זה`) dumps the reason and opens a blank Save-this. Reason likely lost.
- Back from that screen left BNS into a shopping WebView. Relaunch returned to leftover Save-this.
- Tomorrow is not look-only: live checkboxes and "didn't happen" on Sunday 16.
- Calendar Saturday still hides the real day (only `level1 plans`).
- Day title cut off. Unlabeled mic/book/+/sync row.
- Add-event: no time picker, typing appends, 08:00 saved as 10:15. Accidental family-share check.
- Mac not listed on Sync (only Care).

Full writeup + shots: `bns-test/new-menu-report.md`, `menu-00.png`–`menu-26.png`.

---

## Other Level 1 findings same night (also collected)

- Phone Done can undo checks and dump you on Sync (earlier pass). Notes and added plans stayed. Silk law held for Keep; Done did not.
- Calendar vs Today lie on Mac too: ghost 03:07 meeting + 05:00 doctor, no routines.
- iPhone: no BNS. Build died on leftover conflict markers in `day_view.dart`.
- Windows on the physical PC had no app; later installed on Parallels Windows 11 (`BENSHALTIEL4200`) Desktop shortcut `BNS-app`.
- After Ben connected Mac↔phone: note `level1 after pair` crossed to the Mac. Phone calls the Mac **Care**. Mac still also has leftover **Ben Phon**.

---

## Alpha: extra BNS instances show up as extra caregivers on Sync

**Who:** Ben (owner), during alpha. End users will not have this.

**What they were doing:** Opening more than one BNS instance (Mac / phone / extra windows / tester copies). Sync then keeps those other "caregivers" as trusted devices.

**What happened:** The trusted list mixed names: **Ben Phon**, **My BNS Device**, **Care**, leftover Mac/phone identities. Same real phone can appear twice. Opening another instance saves another caregiver into sync.

**Why this is bad (for us, not ship users):** Testers get lost. Pairing windows come back for a friend that already exists. Auto-sync may talk to the wrong copy. Device names default to "My BNS Device" so nothing is distinguishable.

**What they said:** Adjust device names so we are not confused. Extra instances saving other caregivers to sync is problematic. Users won't have this; we are alpha testing.

**What we will do:** Rename live devices to clear names (Phone / Mac). Do not open more instances. Do not pair again. Collect this as an alpha-only sync-identity bug.

**Platforms:** macOS gBNS, Galaxy S23, Parallels Windows BNS, extra debug/release packages.

---

## Fresh instance / share-caregiver — 16 Aug 2026 ~00:27–00:40 IDT

**Who:** Level 1 on Galaxy S23 Ultra. Closed then opened one phone instance (`com.whiteno1se.bns`). No new pair. Stayed on רמה 1.

**Fresh launch:** Today (not leftover Save-this compose, not the 7-card menu). Soft-close banner. Next = morning meds 07:00 part 1/3. Last sync 15 Aug 23:50.

**Share / not share:** L1 copy = nothing leaves unless I choose. Per-item `המשפחה יכולה לדעת` exists on add-event; did not land two new ON/OFF events this pass. Care LAN-on copy is the "give them nothing" door (off = still paired, nothing moves). Toggle tap missed.

**Caregiver:** Bonded friend is **Care** (offline). Could not rename this phone to Phone or Care to Mac without pairing. Pair strip still offers leftover `My BNS Device` / `Ben`. Did not pair, did not unpair, did not flip to L3/L4.

**Annoyed:** Nav ate Done (meds 1/3→3/3 in Settings/Menu). FAB sits on the clipped Settings menu card and opens leftover "זה נעשה?" / put-aside sheets. Tapping L1 (already on) kicks you to Today. Device still `My BNS Device`. Calendar Sat 15 still only `level1 plans`.

**Felt good:** Today cold start. `too tired` stuck in Memories. L1/LAN copy is the right promise. Care still a friend.

Shots: `fresh-00.png`–`fresh-22.png`. Writeup: `fresh-l1.md`.

## Tinker pass — Sunday 16 Aug 2026 after midnight

**Who:** Level 1 on S23. Made a day, jumped days, opened latest doors. No pair. Full-care confirm was a miss-tap, cancelled.

**Felt good**
- **השגרות שלי** opened. Added `midday_water` (every day). Add stuck.
- First-step mode on morning meds. Part 2 Done was silent (no second question that time).
- **מילות היום** exists (Sunday journal).
- Miss copy still kind. Care still listed (offline).
- Quiet mode, widgets 0–7 days (2 selected), owl-time day end, angry door, family forever/context on Save-this.

**Annoyed (app, not OS)**
- Extra LAN instances still appear as extra caregivers (My BNS Device + another Care with Pair).
- Rename to Phone typed, did not persist. Care has no rename, only unpair.
- Full care is one miss-tap away from Settings scroll.
- ☰ often dead. Header Save on keep jumped to Sync. Big Save left BNS to Samsung home.
- Keep `sunday_tinker` **not** on Memories (hidden save).
- Miss reason `sunday_tired` — sheet vanished before save.
- Mon 17 / Tue 18 plans not added: taps ejected to home.
- Sunday 00:30 still has live Done/miss on afternoon/evening routines.
- Done button often has no a11y. Two Done systems. Dual nav.

Shots: `tinker-00`–`tinker-45`. Writeup: `tinker-report.md`.

---
