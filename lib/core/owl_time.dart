/// OWL TIME — the border of the day is chosen, not assumed.
///
/// The owner (2026-08-10): "my day isn't done in 00:00... I cannot set
/// pills at 2:00 and be normal like everyone." The answer is not a longer
/// day (36/48h would break every calendar date) — it is a MOVABLE BORDER:
/// the person says when their day ends (e.g. 04:00), and everything before
/// that hour still belongs to the previous day. Pills at 02:00 sit at the
/// END of tonight's list, after the 23:00 things; the list flips to a new
/// day while the person sleeps, never in their face.
///
/// Everything here is pure and tested. `rolloverHour` 0 = midnight, the
/// exact old behavior; owls pick 1..6. `startHour` is when THIS person
/// begins their day on that same 24-hour entity (Ben: 15:00 → 05:00).
/// One clock — never a second one, never a hardcoded city.
library;

/// The border can sit at most here — a "day" that ends later than 06:00
/// stops being a day, and every guarantee about dates gets murky.
const int kMaxRolloverHour = 6;

int _clampRollover(int rolloverHour) =>
    rolloverHour < 0 ? 0 : (rolloverHour > kMaxRolloverHour ? kMaxRolloverHour : rolloverHour);

/// A day can begin at any clock hour. 0 = midnight (the old world).
const int kMaxStartHour = 23;

int _clampStart(int startHour) =>
    startHour < 0 ? 0 : (startHour > kMaxStartHour ? kMaxStartHour : startHour);

/// When this person-day began (or will begin): the logical date at
/// [startHour]. With start 15:00 / end 05:00: at 16:00 that is today
/// 15:00; at 04:00 that is yesterday 15:00 (still this day); at 06:00
/// the day has already flipped, so it is today 15:00 — still ahead.
DateTime personDayStart(DateTime now, int startHour, int rolloverHour) {
  final logical = logicalDateOf(now, rolloverHour);
  return DateTime(
      logical.year, logical.month, logical.day, _clampStart(startHour));
}

/// The date this moment BELONGS to: before the border, it is still
/// "yesterday" — the night is part of the day it grew out of.
DateTime logicalDateOf(DateTime now, int rolloverHour) {
  final r = _clampRollover(rolloverHour);
  // DateTime normalizes day-1 across month/year borders by itself.
  return DateTime(now.year, now.month, now.day - (now.hour < r ? 1 : 0));
}

/// 'yyyy-MM-dd' of a date — the app's universal day key.
String dayKeyOf(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The day key this moment belongs to, border respected.
String logicalDayKey(DateTime now, int rolloverHour) =>
    dayKeyOf(logicalDateOf(now, rolloverHour));

/// True when [at] belongs to the same person-day as [dayKey].
/// Today’s tiles must not carry Wednesday’s notes into Friday.
bool belongsToLogicalDay(DateTime at, String dayKey, int rolloverHour) =>
    logicalDayKey(at, rolloverHour) == dayKey;

/// Minutes into the PERSON'S day for a clock time. With border 04:00,
/// 23:00 → 1140 and 02:00 → 1320 — the pills sort after the evening,
/// where the night actually lives.
int owlMinutesOf(int hour, int minute, int rolloverHour) {
  final r = _clampRollover(rolloverHour);
  return ((hour * 60 + minute) - r * 60) % (24 * 60); // Dart % ≥ 0
}

/// Where "now" sits inside the person's day (same scale as [owlMinutesOf]).
int owlNowMinutes(DateTime now, int rolloverHour) =>
    owlMinutesOf(now.hour, now.minute, rolloverHour);

/// The REAL moment a logical date + clock time names: a small-hour time
/// (before the border) is the NIGHT of that date — the next calendar day.
/// "Tonight's pills at 02:00" on logical Aug 9 happen at Aug 10, 02:00.
DateTime actualMomentOf(
    DateTime logicalDate, int hour, int minute, int rolloverHour) {
  final r = _clampRollover(rolloverHour);
  return DateTime(logicalDate.year, logicalDate.month,
      logicalDate.day + (hour < r ? 1 : 0), hour, minute);
}

/// THE FUTURE, ON THE PERSON'S CLOCK (level-1 note, 2026-08-17: at
/// Saturday-night 02:00 the calendar already says Sunday, but the
/// person's Saturday is still going — Sunday has not come, and a day
/// that has not come is looked at, never answered).
///
/// [startHour] rides along for API symmetry with the person-day pair in
/// settings; a day that IS the current person-day is answerable at any
/// hour of it — waking before the usual start must not lock the list.
bool isFuturePersonDay(
  DateTime day, {
  required DateTime now,
  required int rolloverHour,
  required int startHour,
}) {
  final logical = logicalDateOf(now, rolloverHour);
  return DateTime(day.year, day.month, day.day).isAfter(logical);
}

/// A day the person may only LOOK at (it has not come yet).
bool lookOnly({
  required DateTime day,
  required DateTime now,
  required int rolloverHour,
  required int startHour,
}) =>
    isFuturePersonDay(day,
        now: now, rolloverHour: rolloverHour, startHour: startHour);

/// Words-side of the same truth (labels ask "has it come?").
bool hasNotCome({
  required DateTime day,
  required DateTime now,
  required int rolloverHour,
  required int startHour,
}) =>
    lookOnly(day: day, now: now, rolloverHour: rolloverHour,
        startHour: startHour);

/// Complete / didn't-happen doors exist only on days that have come.
bool offersCompleteOrSkip({
  required DateTime day,
  required DateTime now,
  required int rolloverHour,
  required int startHour,
}) =>
    !lookOnly(day: day, now: now, rolloverHour: rolloverHour,
        startHour: startHour);

/// The first moment that is no longer this person-day: next logical
/// date at the border hour. With border 0 that is next midnight; with
/// border 05:00, Aug 17 ends at Aug 18 05:00 — 02:00 is still tonight.
DateTime personDayEndExclusive(DateTime now, int rolloverHour) {
  final logical = logicalDateOf(now, rolloverHour);
  return DateTime(
      logical.year, logical.month, logical.day + 1, _clampRollover(rolloverHour));
}

/// True when this clock sits inside the person-day entity
/// (start → owl end). After a 15:00 start, 07:30 is the next morning —
/// not tonight — unless [now] is still before the day begins.
bool inPersonDayWindow({
  required int hour,
  required int minute,
  required DateTime now,
  required int startHour,
  required int rolloverHour,
}) {
  final logical = logicalDateOf(now, rolloverHour);
  final actual = actualMomentOf(logical, hour, minute, rolloverHour);
  final start = personDayStart(now, startHour, rolloverHour);
  final end = personDayEndExclusive(now, rolloverHour);
  return !actual.isBefore(start) && actual.isBefore(end);
}

/// True when [now] has reached this person-day's start.
bool personDayHasStarted(DateTime now, int startHour, int rolloverHour) =>
    !now.isBefore(personDayStart(now, startHour, rolloverHour));

/// Parse "HH:mm" — null when there is no clock (timeless / all-day).
({int hour, int minute})? parseHhmm(String? hhmm) {
  if (hhmm == null || !hhmm.contains(':')) return null;
  final p = hhmm.split(':');
  return (hour: int.tryParse(p[0]) ?? 0, minute: int.tryParse(p[1]) ?? 0);
}

/// When [startHour] is 0 it may mean unset (lived: 15 did not stick).
/// After evening has begun, Next still uses this as the hole start so a
/// leftover 21:45 on a 07:45 stack cannot pretend to be tonight.
const int kImplicitDayStartHour = 15;

/// Evening / night of the person-day — after 15:00, or after midnight
/// before the owl border (04:00 is still tonight).
bool eveningHasBegun(DateTime now, int rolloverHour) {
  final r = _clampRollover(rolloverHour);
  return now.hour >= kImplicitDayStartHour || now.hour < r;
}

/// The start hour the hole uses for Next. A set start wins. Unset 0
/// becomes 15 once evening has begun — not a midnight that swallows
/// the morning stack into tonight.
int nextHoleStartHour(int startHour, DateTime now, int rolloverHour) {
  if (startHour > 0) return startHour;
  return eveningHasBegun(now, rolloverHour) ? kImplicitDayStartHour : 0;
}

/// After the day has started, a slot in the owl hole (between the
/// border and the start — 05:00–15:00 for Ben) is the *next* morning,
/// not tonight's הבא. A 04:00 owl slot is still this day. Before the
/// day starts, the hole is just this calendar morning and may be next.
///
/// [usualHhmm] is the routine's ordinary clock. A leftover evening
/// override on a morning stack must not become tonight's הבא — even
/// when startHour is 0 (unset), once evening has begun.
bool isNextMorningSlot({
  String? usualHhmm,
  String? todayHhmm,
  required DateTime now,
  required int startHour,
  required int rolloverHour,
}) {
  if (startHour > 0 &&
      !personDayHasStarted(now, startHour, rolloverHour)) {
    return false;
  }
  if (startHour == 0 && !eveningHasBegun(now, rolloverHour)) {
    return false;
  }
  final holeStart = nextHoleStartHour(startHour, now, rolloverHour);
  final raw = usualHhmm ?? todayHhmm;
  final parsed = parseHhmm(raw);
  if (parsed == null) return false;
  return !inPersonDayWindow(
    hour: parsed.hour,
    minute: parsed.minute,
    now: now,
    startHour: holeStart,
    rolloverHour: rolloverHour,
  );
}

/// "What's next" rank inside one person-day.
/// 0 = still ahead tonight (nearest first)
/// 1 = earlier tonight — walks FORWARD (evening meds before 21:30)
/// 2 = timeless
/// 3 = next-morning hole after the day started (visible, never הבא)
int nextPersonDayRank({
  required int? owlMinutes,
  required int nowOwl,
  required bool isNextMorning,
}) {
  if (owlMinutes == null || owlMinutes >= 24 * 60) return 2;
  if (isNextMorning) return 3;
  return owlMinutes >= nowOwl ? 0 : 1;
}

/// Sort two next-rank keys. Same rank walks the person-day forward
/// (earlier clock first). Rank 1 must not jump backward to 21:30
/// while later-today evening work is still open.
int compareNextPersonDay(int am, int bm, int ra, int rb) {
  if (ra != rb) return ra.compareTo(rb);
  return am.compareTo(bm);
}

/// The person-day clock across a copy / Care merge.
///
/// 0 means unset (midnight, the old world, or a file that never knew
/// the field). A helper's 0 must not eat a set 15. A set incoming
/// hour always wins — Care learns the person's day; the person keeps
/// it when Care sends the default back.
int adoptPersonDayHour({
  required int incoming,
  required int local,
  bool incomingIsHelper = false,
}) {
  if (incomingIsHelper) return local;
  if (incoming == 0 && local != 0) return local;
  return incoming;
}
