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
