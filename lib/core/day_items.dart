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
///
/// [startHour] is when THIS person-day begins (Ben: 15:00 → 05:00). The
/// timeline (morning→night) stays owl-steady. "What's next" uses the
/// hole: after the day starts, 07:30 is the next morning — visible, not
/// הבא — while evening/night still ahead is the real next.
List<Object> weaveDayList({
  required List<Routine> routines,
  required List<CalendarEvent> plans,
  required Set<String> doneRoutineIds,
  required Set<String> skippedRoutineIds,
  required bool nextFirst,
  required DateTime now,
  int rolloverHour = 0,
  int startHour = 0,
}) {
  final dayKey = logicalDayKey(now, rolloverHour);
  int minutesOf(Object item) {
    String? t;
    // A later-today override sorts by TODAY'S clock, not the usual one.
    if (item is Routine) t = item.timeOn(dayKey);
    if (item is CalendarEvent) t = item.isAllDay ? null : item.time;
    if (t == null) return 24 * 60; // timeless goes last
    final p = parseHhmm(t);
    if (p == null) return 24 * 60;
    return owlMinutesOf(p.hour, p.minute, rolloverHour);
  }

  bool nextMorningOf(Object item) {
    String? usual;
    String? today;
    if (item is Routine) {
      usual = item.time;
      today = item.timeOn(dayKey);
    } else if (item is CalendarEvent && !item.isAllDay) {
      usual = item.time;
      today = item.time;
    }
    return isNextMorningSlot(
      usualHhmm: usual,
      todayHhmm: today,
      now: now,
      startHour: startHour,
      rolloverHour: rolloverHour,
    );
  }

  // NOTE: doneRoutineIds / skippedRoutineIds no longer move anything —
  // they stay in the signature because answering is still part of the
  // day's story (tiles read them) and callers already gather them.
  final nowMin = owlNowMinutes(now, rolloverHour);
  final list = <Object>[...routines, ...plans];
  list.sort((a, b) {
    final am = minutesOf(a), bm = minutesOf(b);
    if (!nextFirst) return am.compareTo(bm);
    // "What's next" walks the person-day from now: still-ahead tonight
    // first, then earlier today nearest the person (evening beats a
    // morning that already passed), then timeless, then the next
    // morning sitting in the owl hole. Answered tiles hold their spot.
    final ra = nextPersonDayRank(
      owlMinutes: am,
      nowOwl: nowMin,
      isNextMorning: nextMorningOf(a),
    );
    final rb = nextPersonDayRank(
      owlMinutes: bm,
      nowOwl: nowMin,
      isNextMorning: nextMorningOf(b),
    );
    return compareNextPersonDay(am, bm, ra, rb);
  });
  return list;
}

/// Id of a woven day item (routine or plan).
String dayItemId(Object item) =>
    item is Routine ? item.id : (item as CalendarEvent).id;

/// Title of a woven day item.
String dayItemTitle(Object item) =>
    item is Routine ? item.title : (item as CalendarEvent).title;

/// Clock time of a woven day item — null for timeless / all-day plans.
/// Pass [dayKey] (or [now] + [rolloverHour]) so a today-only postpone
/// shows 17:30 today and the usual time on any other logical day.
String? dayItemTime(
  Object item, {
  String? dayKey,
  DateTime? now,
  int rolloverHour = 0,
}) {
  final key = dayKey ?? (now != null ? logicalDayKey(now, rolloverHour) : null);
  if (item is Routine) return item.timeOn(key);
  if (item is CalendarEvent) return item.isAllDay ? null : item.time;
  return null;
}

/// Open (unanswered) routines AND plans in "what's next" clock order.
///
/// This is the list the Next hero, Coming up, and the thin "Just this one"
/// walk share. A doctor visit at 10:00 can be Next — plans are not a
/// second list (owner, 2026-08-09 / 2026-08-15).
///
/// Answered items (routine ✓ / skip, plan ✓ / didn't-happen) leave this
/// list, so the next open thing stands in place. The person-day pair
/// ([rolloverHour] + [startHour]) is the same border as the rest of Today.
List<Object> openDayItemsInNextOrder({
  required List<Routine> routines,
  required List<CalendarEvent> plans,
  required Set<String> doneRoutineIds,
  required Set<String> skippedRoutineIds,
  required DateTime now,
  int rolloverHour = 0,
  int startHour = 0,
}) {
  final openRoutines = routines
      .where((r) =>
          !doneRoutineIds.contains(r.id) && !skippedRoutineIds.contains(r.id))
      .toList();
  final openPlans = plans.where((p) => !p.isAnswered).toList();
  return weaveDayList(
    routines: openRoutines,
    plans: openPlans,
    doneRoutineIds: const {},
    skippedRoutineIds: const {},
    nextFirst: true,
    now: now,
    rolloverHour: rolloverHour,
    startHour: startHour,
  );
}
