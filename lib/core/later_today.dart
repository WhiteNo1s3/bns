/// LATER TODAY — still this day, just a later clock.
///
/// Not a skip. Not "didn't happen". The person still wants to do it;
/// the hour moved. Quarter-hours only, from now+15 minutes through the
/// END of THIS person-day (the day entity: start → owl-time end).
/// Tomorrow is not offered — nobody can do tomorrow today.
///
/// PURE: no plugin, no store. The UI shows the slots; Today writes a
/// one-day override for a recurring routine (usual time comes back
/// tomorrow) and updates the plan's own time (that visit is only today).
library;

import 'package:bns/core/owl_time.dart';

/// First quarter-hour that is at least [from] (seconds snap the minute up).
DateTime snapUpToQuarter(DateTime from) {
  var minutes = from.hour * 60 + from.minute;
  if (from.second > 0 || from.millisecond > 0 || from.microsecond > 0) {
    minutes += 1;
  }
  final rem = minutes % 15;
  if (rem != 0) minutes += 15 - rem;
  return DateTime(from.year, from.month, from.day).add(Duration(minutes: minutes));
}

String formatHhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The first moment that is no longer this person-day: the next logical
/// date at the border hour. With border 0 that is next midnight; with
/// border 04:00, Aug 9 ends at Aug 10 04:00 — 02:00 is still tonight.
DateTime laterTodayEndExclusive(DateTime now, int rolloverHour) =>
    personDayEndExclusive(now, rolloverHour);

/// Later quarter-hours still belonging to this person-day.
///
/// Empty when nothing later remains (late night, or the next slot would
/// be tomorrow). Never invents tomorrow. [startHour] is the same day
/// entity as owl time — slots never begin before the person-day starts.
List<String> laterTodaySlots({
  required DateTime now,
  int rolloverHour = 0,
  int startHour = 0,
}) {
  var first = snapUpToQuarter(now.add(const Duration(minutes: 15)));
  final dayStart = personDayStart(now, startHour, rolloverHour);
  if (first.isBefore(dayStart)) first = dayStart;
  final end = laterTodayEndExclusive(now, rolloverHour);
  if (!first.isBefore(end)) return const [];
  final slots = <String>[];
  var t = first;
  // A day is at most 24h of quarter-hours (96). Hard cap so a bad clock
  // can never loop.
  for (var i = 0; i < 96 && t.isBefore(end); i++) {
    slots.add(formatHhmm(t));
    t = t.add(const Duration(minutes: 15));
  }
  return slots;
}

/// True when [hhmm] is a later-today slot right now (not already past,
/// not tomorrow, not before this person-day starts).
bool isLaterTodaySlot(
  String hhmm, {
  required DateTime now,
  int rolloverHour = 0,
  int startHour = 0,
}) =>
    laterTodaySlots(
      now: now,
      rolloverHour: rolloverHour,
      startHour: startHour,
    ).contains(hhmm);
