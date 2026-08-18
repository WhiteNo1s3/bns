/// THE REASON TO WAKE (owner as user, 2026-08-18: "many days have nothing
/// to wake up for and I do have"). The wake alarm never rings empty — its
/// body is the day's opening: the first things waiting, in the order of
/// the person's own clock. Pure and tested; the notification layer only
/// delivers what this builds.
library;

import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';

/// The first things of [day], woven in owl order, as one warm line —
/// e.g. "תרופות בוקר 08:00 · בדיקת דם 09:30 · הליכה". At most three;
/// an empty day still gives a reason to stand up.
String wakeBodyFor({
  required List<Routine> routines,
  required List<CalendarEvent> events,
  required DateTime day,
  required int rolloverHour,
  required String Function(String en, String he) t,
}) {
  final dayKey = dayKeyOf(DateTime(day.year, day.month, day.day));

  int sortKey(String? hhmm) {
    final p = parseHhmm(hhmm);
    if (p == null) return 24 * 60; // timeless things close the line
    return owlMinutesOf(p.hour, p.minute, rolloverHour);
  }

  final entries = <({int key, String words})>[];
  for (final r in routines) {
    if (!r.appliesOn(day)) continue;
    final hhmm = r.timeOn(dayKey);
    entries.add((
      key: sortKey(hhmm),
      words: hhmm == null ? r.title : '${r.title} $hhmm',
    ));
  }
  for (final e in events) {
    if (e.date != dayKey) continue;
    entries.add((
      key: sortKey(e.time),
      words: e.time == null ? e.title : '${e.title} ${e.time}',
    ));
  }

  if (entries.isEmpty) {
    return t('Your day is waiting for you.', 'היום שלך מחכה לך.');
  }
  entries.sort((a, b) => a.key.compareTo(b.key));
  return entries.take(3).map((e) => e.words).join(' · ');
}
