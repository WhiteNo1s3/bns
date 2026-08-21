/// THE DAY STARTS WHEN YOU WAKE (owner, 2026-08-21: "I want the start of
/// the day to start the routine just like in normal day that you wake up
/// like a normie, I want to push the entity of the routine into whatever
/// hour the user woke up... it just needs to move to the day of a user
/// that wakes up in different hours").
///
/// The routine is a SHAPE, not a set of clock times. Its head is the first
/// routine of the person-day (owl order — the 02:00 water never leads the
/// morning). When the person says קמתי, the head slides to the moment they
/// woke and every routine of today follows by its own gap — TODAY ONLY,
/// through the same per-day overrides שינוי שעה writes, so the list, הבא,
/// the reminders, the day view and the Care seat all follow for free.
/// Plans and events stay on the clock (a doctor at 10:00 does not move);
/// answered rows stay where they were answered; a row the person already
/// moved today keeps their move. Quarter hours only, nothing past the
/// day's border. Pure and tested.
library;

import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';

/// The head of today's shape: the usual clock of the earliest timed
/// routine in person-day order. Null when nothing today has a clock.
String? dayHeadTime({
  required List<Routine> routines,
  required DateTime day,
  required int rolloverHour,
}) {
  String? head;
  int? headKey;
  for (final r in routines) {
    if (!r.appliesOn(day)) continue;
    final p = parseHhmm(r.time);
    if (p == null) continue;
    final key = owlMinutesOf(p.hour, p.minute, rolloverHour);
    if (headKey == null || key < headKey) {
      headKey = key;
      head = r.time;
    }
  }
  return head;
}

/// 'HH:mm' rounded to the nearest quarter hour ("2:07 doesn't exist
/// here" — owner law). 23:53 rounds up to 00:00 of the same owl scale,
/// which callers clamp before the border.
String snapToQuarterHhmm(String hhmm) {
  final p = parseHhmm(hhmm);
  if (p == null) return hhmm;
  var total = p.hour * 60 + p.minute;
  total = ((total + 7) ~/ 15) * 15;
  total %= 24 * 60;
  return _hhmm(total);
}

String _hhmm(int minutesOfDay) {
  final m = minutesOfDay % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// Today's clocks after waking at [wokeAt] ('HH:mm'): routine id → the
/// hour it should wear TODAY. Only routines that would actually move are
/// returned. Empty when there is no head, or the head already sits at
/// the wake hour.
///
/// [answeredIds] (done or skipped today) never move. A routine that
/// already carries an override for [dayKey] keeps the person's own move.
Map<String, String> wakeAnchoredTimes({
  required List<Routine> routines,
  required DateTime day,
  required String dayKey,
  required String wokeAt,
  required int rolloverHour,
  Set<String> answeredIds = const {},
}) {
  final head = dayHeadTime(
      routines: routines, day: day, rolloverHour: rolloverHour);
  final hp = parseHhmm(head);
  final wp = parseHhmm(snapToQuarterHhmm(wokeAt));
  if (hp == null || wp == null) return const {};

  final headOwl = owlMinutesOf(hp.hour, hp.minute, rolloverHour);
  final wokeOwl = owlMinutesOf(wp.hour, wp.minute, rolloverHour);
  final shift = wokeOwl - headOwl;
  if (shift == 0) return const {};

  const lastSlot = 24 * 60 - 15; // the day's last quarter, before the border
  final border = rolloverHour.clamp(0, 6) * 60;

  final out = <String, String>{};
  for (final r in routines) {
    if (!r.appliesOn(day)) continue;
    if (answeredIds.contains(r.id)) continue;
    final usual = parseHhmm(r.time);
    if (usual == null) continue;
    final ov = r.timeByDay[dayKey];
    if (ov != null && ov.isNotEmpty) continue; // their own move today wins

    var owl = owlMinutesOf(usual.hour, usual.minute, rolloverHour) + shift;
    if (owl < 0) owl = 0;
    if (owl > lastSlot) owl = lastSlot;
    // Back to the wall clock, then to a quarter.
    final clock = snapToQuarterHhmm(_hhmm(owl + border));
    // A snap can land exactly on the border (24h wraps) — keep it inside.
    final cp = parseHhmm(clock)!;
    final clockOwl = owlMinutesOf(cp.hour, cp.minute, rolloverHour);
    final safe = clockOwl > lastSlot ? _hhmm(lastSlot + border) : clock;
    if (safe != r.timeOn(dayKey)) out[r.id] = safe;
  }
  return out;
}

/// 'HH:mm' of the wake kept for [dayKey] in settings ('yyyy-MM-dd HH:mm'),
/// or null when that day was never anchored.
String? wokeAtFor(String wokeAtSetting, String dayKey) {
  final s = wokeAtSetting.trim();
  if (s.length < 16 || !s.startsWith(dayKey)) return null;
  final hhmm = s.substring(11, 16);
  return parseHhmm(hhmm) == null ? null : hhmm;
}
