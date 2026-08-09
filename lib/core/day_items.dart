/// PURE weaving of one day's list — routines and plans together, one clock.
/// A plan (a one-time thing: a doctor appointment, something for today)
/// stands IN the day with the same weight as a gentle step (owner,
/// 2026-08-09), under the exact same laws:
///   - answered things sink (a ✓ or a said "didn't happen" both count);
///   - the clock orders what's open (morning→night, or "what's next" when
///     the person chose that);
///   - timeless things close the list.
library;

import 'package:bns/core/models/models.dart';

/// Items are [Routine] or [CalendarEvent] — the UI switches on the type.
List<Object> weaveDayList({
  required List<Routine> routines,
  required List<CalendarEvent> plans,
  required Set<String> doneRoutineIds,
  required Set<String> skippedRoutineIds,
  required bool nextFirst,
  required DateTime now,
}) {
  int minutesOf(Object item) {
    String? t;
    if (item is Routine) t = item.time;
    if (item is CalendarEvent) t = item.isAllDay ? null : item.time;
    if (t == null) return 24 * 60; // timeless goes last
    final p = t.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool answered(Object item) {
    if (item is Routine) {
      return doneRoutineIds.contains(item.id) ||
          skippedRoutineIds.contains(item.id);
    }
    return (item as CalendarEvent).isAnswered;
  }

  final nowMin = now.hour * 60 + now.minute;
  final list = <Object>[...routines, ...plans];
  list.sort((a, b) {
    final aDone = answered(a);
    final bDone = answered(b);
    if (aDone != bDone) return aDone ? 1 : -1; // handled sinks
    final am = minutesOf(a), bm = minutesOf(b);
    if (!nextFirst) return am.compareTo(bm);
    // "What's next": upcoming (>= now) first by nearness, then the
    // earlier-today ones, then timeless.
    int rank(int m) => m >= 24 * 60 ? 2 : (m >= nowMin ? 0 : 1);
    final ra = rank(am), rb = rank(bm);
    if (ra != rb) return ra.compareTo(rb);
    return am.compareTo(bm);
  });
  return list;
}
