# changes.md

Shipped in the 2026-08-14–15 iterate on this tree (`~/dev/gBNS`).  
For Grok, Cursor, and any local model: this is the list to test. Laws stay in AGENTS.md.

Working copy: this folder. Do not treat Windows `C:\Dev\bns` as current.

---

## 2026-08-17 — Skip reason sticks on Close

**Feel:** Write «too late» / עייף on the miss sheet. Hit **סגירה** or tap out. The skip is logged with those words. The item leaves Today. Nobody is sent to a second Save screen.

**What**
- Close / tap-out / back with a non-empty reason logs the skip (same as «זה לא קרה היום»).
- Empty Close just closes. No skip. Nobody is forced.
- One door: the reason on the sheet IS the skip. The capture bar is gone from this sheet.
- Confirm sits above the keyboard.
- In-sheet mic stays on the field. Shade «לא קרה — לספר למה» opens this sheet on Today, not `/capture`.
- Plan sheet and day-view skip use the same Close rule. No English «Skipped: » prefix.

**Files**
- `lib/core/didnt_happen.dart`, `lib/ui/widgets/didnt_happen_sheet.dart`
- `lib/main.dart` (Today + plan + shade landing)
- `lib/features/calendar/day_view.dart`
- `lib/core/reminder_plan.dart`, `lib/services/notifications_service.dart`
- `test/didnt_happen_test.dart`, `test/reminder_plan_test.dart`

**Live test**
1. Today: long-press a routine, type עייף, hit סגירה. Item is skipped. The why is on the tile.
2. Same with a plan. Empty Close leaves it on Today.
3. Shade «לא קרה — לספר למה»: the miss sheet opens. Words land on the skip, not only in Memories.
4. Day view skip: Hebrew words, Close, skip logged. No «Skipped: » in the reason.

---

## 2026-08-17 — One quiet ✓, the day does not jump

**Feel:** Tap **בוצע** / It's done. A quiet ✓ sits on the same tile, same clock. Nobody asks again. Nobody leaves Today. The list does not jump.

**What**
- L1–2 Today: no “Is it done?” / “זה נעשה?” dialog. A tap is the answer.
- Done does not push `/sync` or any other screen.
- Weave order unchanged (morning→night / owl). Next skips done items. A done 08:00 at 20:30 is not Next.
- L4 (`guidedMode`) may still ask. Skip path unchanged.
- FAB clearance under the list so leftover actions are not covered.

**Files**
- `lib/main.dart` (`_toggleComplete`, `_togglePlanDone`, `_markNextDone`)
- `lib/core/day_items.dart` (`todayDoneNeedsConfirm`)
- `test/day_items_test.dart`, `test/today_order_test.dart`

**Live test**
- Did Done stay a quiet ✓ without asking again or leaving Today?

---

## 2026-08-15 — Person-day + later today (today only)

**Feel:** The day is *theirs*. Ben can start at 15:00 and end at 05:00. If 15:00 will not work, **עוד היום** / Later today moves it later *inside that day*. Tomorrow the usual time comes back.

**What**
- `AppSettings.dayStartHour` (0–23) + existing `dayRolloverHour` (0–6 end). Sync screen: when the day starts, when it ends.
- Later-today slots = now+15 (quarter hours) through the *person-day* end. 17:30 and 02:00 yes; 06:00 no if the day ends at 05:00.
- Routines: `time` stays the usual clock. `timeByDay` is a one-day override (`yyyy-MM-dd` logical day → `HH:mm`). Next person-day uses `time` again.
- One-time plans: changing `time` is fine (that visit is only that day).
- Reminders follow the **device system clock**, and the override, then the usual time.

**Files**
- `lib/core/owl_time.dart`, `lib/core/later_today.dart`, `lib/ui/widgets/later_today_door.dart`
- `lib/core/models/routine.dart` (`timeByDay`, `timeOn`, `postponeOn`)
- `lib/core/models/settings.dart` (`dayStartHour`)
- `lib/main.dart` (`_postponeItem`), Next card + routine/plan tiles
- `lib/features/sync/sync_screen.dart`
- `test/later_today_test.dart`, `test/owl_time_test.dart`

**Live test**
1. Sync: day starts 15:00, ends 05:00.
2. A 15:00 plan or routine: tap **עוד היום**, pick 17:30. Next and the list show 17:30. Reminder is 17:30 on the phone clock.
3. After the person-day ends (or a new logical day): usual time is 15:00 again.
4. At 16:00, later-today includes 17:30 and 02:00, not 06:00.

---

## 2026-08-15 — Plans stand in Next and Coming up

**Feel:** A 10:00 doctor visit is the big Next card if nothing else is sooner. Quiet **תוכנית**. **בוצע** / **משהו הפריע**. Coming up includes it. Not only the list below.

**What**
- `openDayItemsInNextOrder` — unanswered routines AND plans, owl-time order.
- Next hero + Coming up use that list.
- Thin door **רק את זה** / Just this one (same list).
- Day view: quiet answered-plan ✓.

**Files**
- `lib/core/day_items.dart`, `lib/ui/widgets/next_hero_card.dart`, `lib/main.dart`
- `lib/features/calendar/day_view.dart`
- `test/day_items_test.dart`, `test/today_order_test.dart`, `test/next_order_test.dart`

**Live test**
- Add a doctor plan for later this morning. Open Today. It stands in the big card, not only below.

---

## 2026-08-15 — Reminders use the phone's clock

**Feel:** 02:00 on the phone is 02:00, in whatever zone the system is set to. Travel or change the clock, reminders follow. Not UTC. Not Jerusalem.

**What**
- `flutter_timezone` binds `tz.local` to the device IANA name.
- `lib/core/reminder_timezone.dart` builds wall-clock `TZDateTime`s.
- Owl-time night pills still belong to tonight.

**Files**
- `lib/core/reminder_timezone.dart`, `lib/services/notifications_service.dart`, `pubspec.yaml`
- `test/reminder_timezone_test.dart`

**Live test**
- Set a reminder two minutes out. It arrives at that minute, not ~3 hours off. After reboot, 02:00 is still 02:00.

---

## 2026-08-15 — Android file-ear (one speak)

**Feel:** Talk, stop, words from *that* recording land under הקלטה 1. No second listen sheet. Voice is already kept if words fail. Waze card only if the file ear heard nothing.

**What**
- On-device `SpeechRecognizer` + `EXTRA_AUDIO_SOURCE` (API 33+). Reads the kept WAV. Does not open the mic (never beside the recorder).
- `_hearWords` ladder: Apple file ear, Android file ear, Whisper, Vosk.
- Hebrew `he-IL` / `iw-IL`. Need an on-device speech pack.

**Files**
- `lib/services/android_file_stt.dart`, `android/.../AndroidFileStt.kt`, `MainActivity.kt`
- `lib/features/capture/quick_capture_screen.dart`
- `test/android_file_stt_test.dart`

**Live test**
- After a voice note, do Hebrew words appear with no listen-chime? Two takes, both playable? If empty: Settings → on-device speech, Hebrew pack.

---

## How a local model should test
1. Read AGENTS.md + this file.
2. `flutter test` (at least the files named in the block you are checking).
3. Answer only the live-test questions. Pass / fail / what you changed.
4. Do not add features during a test pass unless the owner asked.
