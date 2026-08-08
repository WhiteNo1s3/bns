/// PURE reminder planning — which reminders should exist right now, given
/// the routines, the plans and the person's choices. No plugin, no platform,
/// no side effects: the notifications service turns this plan into real
/// scheduled notifications, and tests can check the decisions directly.
library;

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';

/// How a planned reminder repeats.
enum PlannedRepeat {
  /// One-shot (a plan on the calendar): fires once and is gone.
  none,

  /// Every day at the same time (a daily routine).
  daily,

  /// Every week on the same weekday + time (weekly / custom routines).
  weekly,
}

/// One reminder that should be scheduled.
class PlannedReminder {
  /// Stable notification id (deterministic per source item).
  final int id;
  final String title;
  final String body;

  /// First moment it should fire, local time. Always in the future.
  final DateTime firstAt;
  final PlannedRepeat repeat;

  /// 'routine:<id>' or 'event:<id>:<yyyy-MM-dd>' — the tap knows where home is.
  final String payload;

  const PlannedReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.firstAt,
    required this.repeat,
    required this.payload,
  });
}

/// Plans (calendar events) further away than this get no reminder yet —
/// the horizon rolls forward as days pass (rescheduling is cheap and
/// happens on every data change and every app start).
const int kEventReminderHorizonDays = 14;

/// iOS allows ~64 pending notifications total; keep plans well under it so
/// routines always have room.
const int kMaxEventReminders = 20;

List<PlannedReminder> planReminders({
  required List<Routine> routines,
  required List<CalendarEvent> events,
  required AppSettings settings,
  required DateTime now,
}) {
  // A CAREGIVER IS NOT THE PATIENT (owner, 2026-07-27): the helper's device
  // carries the other person's day but must never buzz about it.
  if (!settings.notificationsEnabled || settings.caregiverDevice) {
    return const [];
  }

  final planned = <PlannedReminder>[];

  // ---- Routines: repeating, at their own time, on their own days ----
  for (final r in routines) {
    if (!r.isActive || r.time == null) continue;
    final hm = _parseTime(r.time!);
    if (hm == null) continue;

    switch (r.recurrenceType) {
      case RecurrenceType.daily:
        planned.add(PlannedReminder(
          id: _stableId('r.${r.id}'),
          title: L.t('Gentle reminder', 'תזכורת עדינה'),
          body: L.t('${r.title} — whenever you\'re ready',
              '${r.title} — מתי שנוח לך'),
          firstAt: _nextDailyOccurrence(now, hm.$1, hm.$2),
          repeat: PlannedRepeat.daily,
          payload: 'routine:${r.id}',
        ));
      case RecurrenceType.weekdays:
      case RecurrenceType.weekly:
      case RecurrenceType.custom:
        // 0=Sun ... 6=Sat (the app's convention). A weekly reminder per day
        // it applies — so a Tuesday-only routine never buzzes on Friday.
        final days = r.recurrenceType == RecurrenceType.weekdays
            ? const [1, 2, 3, 4, 5]
            : r.daysOfWeek;
        for (final dow in days.toSet()) {
          if (dow < 0 || dow > 6) continue;
          planned.add(PlannedReminder(
            id: _stableId('r.${r.id}.$dow'),
            title: L.t('Gentle reminder', 'תזכורת עדינה'),
            body: L.t('${r.title} — whenever you\'re ready',
                '${r.title} — מתי שנוח לך'),
            firstAt: _nextWeeklyOccurrence(now, dow, hm.$1, hm.$2),
            repeat: PlannedRepeat.weekly,
            payload: 'routine:${r.id}',
          ));
        }
    }
  }

  // ---- Plans (calendar events with a time): one heads-up, a bit before ----
  final lead = settings.eventReminderMinutes;
  if (lead >= 0) {
    final horizon = now.add(const Duration(days: kEventReminderHorizonDays));
    final upcoming = <(DateTime, CalendarEvent)>[];
    for (final e in events) {
      if (e.isAllDay || e.time == null) continue;
      final hm = _parseTime(e.time!);
      final date = DateTime.tryParse(e.date);
      if (hm == null || date == null) continue;
      final at = DateTime(date.year, date.month, date.day, hm.$1, hm.$2);
      final remindAt = at.subtract(Duration(minutes: lead));
      if (!remindAt.isAfter(now) || at.isAfter(horizon)) continue;
      upcoming.add((remindAt, e));
    }
    upcoming.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (remindAt, e) in upcoming.take(kMaxEventReminders)) {
      final hhmm = e.time!;
      planned.add(PlannedReminder(
        id: _stableId('e.${e.id}'),
        title: L.t('Coming up', 'מתקרב'),
        body: L.t('${e.title} — at $hhmm. No rush, just so it doesn\'t slip away.',
            '${e.title} — בשעה $hhmm. בלי לחץ, רק כדי שזה לא יברח.'),
        firstAt: remindAt,
        repeat: PlannedRepeat.none,
        payload: 'event:${e.id}:${e.date}',
      ));
    }
  }

  return planned;
}

/// Where a tapped reminder should land: routines go home to Today; a plan
/// opens the day it lives on.
String routeForReminderPayload(String? payload) {
  if (payload == null) return '/';
  final parts = payload.split(':');
  if (parts.length >= 3 && parts[0] == 'event') {
    return '/day?date=${parts[2]}';
  }
  return '/';
}

/// A quick fingerprint of everything reminders depend on. When it hasn't
/// changed, rescheduling is skipped — the data store persists on every tap
/// and ✓, and re-registering dozens of alarms each time would be waste.
String reminderFingerprint({
  required List<Routine> routines,
  required List<CalendarEvent> events,
  required AppSettings settings,
  required DateTime now,
}) {
  final b = StringBuffer()
    ..write(L.lang)
    ..write('|${now.year}-${now.month}-${now.day}')
    ..write('|${settings.notificationsEnabled}')
    ..write('|${settings.caregiverDevice}')
    ..write('|${settings.reminderStyle}')
    ..write('|${settings.notificationColor}')
    ..write('|${settings.relaxingPalette.name}')
    ..write('|${settings.eventReminderMinutes}');
  for (final r in routines) {
    if (!r.isActive || r.time == null) continue;
    b.write('|r:${r.id},${r.title},${r.time},${r.recurrenceType.name},'
        '${(r.daysOfWeek.toList()..sort()).join('.')}');
  }
  final horizon = now.add(const Duration(days: kEventReminderHorizonDays + 1));
  for (final e in events) {
    if (e.isAllDay || e.time == null) continue;
    final date = DateTime.tryParse(e.date);
    if (date == null || date.isAfter(horizon)) continue;
    b.write('|e:${e.id},${e.title},${e.date},${e.time}');
  }
  return b.toString();
}

/// Deterministic, positive 31-bit id from a stable key (String.hashCode is
/// not guaranteed stable across VM builds; this is).
int _stableId(String key) {
  var h = 0;
  for (final unit in key.codeUnits) {
    h = 0x1fffffff & (h + unit);
    h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
    h ^= h >> 6;
  }
  h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
  h ^= h >> 11;
  return 0x1fffffff & (h + ((0x00003fff & h) << 15));
}

(int, int)? _parseTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return null;
  }
  return (h, m);
}

DateTime _nextDailyOccurrence(DateTime now, int hour, int minute) {
  var at = DateTime(now.year, now.month, now.day, hour, minute);
  if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
  return at;
}

DateTime _nextWeeklyOccurrence(DateTime now, int dow, int hour, int minute) {
  // dow: 0=Sun ... 6=Sat; DateTime.weekday: Mon=1 ... Sun=7.
  // Dart's % is never negative for a positive divisor.
  final todayDow = now.weekday % 7;
  final daysAhead = (dow - todayDow) % 7;
  var at = DateTime(now.year, now.month, now.day, hour, minute)
      .add(Duration(days: daysAhead));
  if (!at.isAfter(now)) at = at.add(const Duration(days: 7));
  return at;
}
