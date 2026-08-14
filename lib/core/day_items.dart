/// PURE weaving of one day's list — routines and plans together, one clock.
/// A plan (a one-time thing: a doctor appointment, something for today)
/// stands IN the day with the same weight as a gentle step (owner,
/// 2026-08-09), under the exact same laws:
///   - THE DAY STAYS STEADY (owner, 2026-08-14: "the day should remain
///     steady, not the past actions"): answering never moves a tile. The
///     old "answered sinks" reshuffled the list under the person's finger —
///     a ✓ is a state shown in place, not a move;
///   - the clock orders the day (morning→night, or "what's next" when
///     the person chose that);
///   - timeless things close the list.
library;

import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';

/// Items are [Routine] or [CalendarEvent] — the UI switches on the type.
///
/// [rolloverHour] is the person's day border (owl time): with border 04:00,
/// the 02:00 pills sort AFTER the 23:00 wind-down — the night belongs to
/// tonight. 0 keeps the old midnight world exactly.
List<Object> weaveDayList({
  required List<Routine> routines,
  required List<CalendarEvent> plans,
  required Set<String> doneRoutineIds,
  required Set<String> skippedRoutineIds,
  required bool nextFirst,
  required DateTime now,
  int rolloverHour = 0,
}) {
  int minutesOf(Object item) {
    String? t;
    if (item is Routine) t = item.time;
    if (item is CalendarEvent) t = item.isAllDay ? null : item.time;
    if (t == null) return 24 * 60; // timeless goes last
    final p = t.split(':');
    return owlMinutesOf(
        int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0, rolloverHour);
  }

  // NOTE: doneRoutineIds / skippedRoutineIds no longer move anything —
  // they stay in the signature because answering is still part of the
  // day's story (tiles read them) and callers already gather them.
  final nowMin = owlNowMinutes(now, rolloverHour);
  final list = <Object>[...routines, ...plans];
  list.sort((a, b) {
    final am = minutesOf(a), bm = minutesOf(b);
    if (!nextFirst) return am.compareTo(bm);
    // "What's next": upcoming (>= now) first by nearness, then the
    // earlier-today ones, then timeless. Answered tiles hold their spot —
    // steady beats sorted (owner, 2026-08-14).
    int rank(int m) => m >= 24 * 60 ? 2 : (m >= nowMin ? 0 : 1);
    final ra = rank(am), rb = rank(bm);
    if (ra != rb) return ra.compareTo(rb);
    return am.compareTo(bm);
  });
  return list;
}
