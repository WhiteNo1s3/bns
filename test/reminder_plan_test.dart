import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/reminder_plan.dart';

void main() {
  L.lang = 'en'; // deterministic copy in assertions

  final created = DateTime(2026, 8, 1);

  Routine routine(
    String id, {
    String? time,
    RecurrenceType type = RecurrenceType.daily,
    List<int> days = const [],
    bool active = true,
  }) =>
      Routine(
        id: id,
        title: 'Routine $id',
        recurrenceType: type,
        daysOfWeek: days,
        time: time,
        isActive: active,
        createdAt: created,
        updatedAt: created,
      );

  CalendarEvent event(String id, String date, String? time,
          {bool allDay = false}) =>
      CalendarEvent(
        id: id,
        title: 'Plan $id',
        date: date,
        time: time,
        isAllDay: allDay,
        createdAt: created,
        updatedAt: created,
      );

  const settings = AppSettings();
  // 2026-08-08 is a Saturday (dow 6); 10:00 in the morning.
  final now = DateTime(2026, 8, 8, 10, 0);

  group('planReminders — routines', () {
    test('daily routine gets one daily repeat at the next occurrence', () {
      final plan = planReminders(
        routines: [routine('a', time: '08:00')],
        events: const [],
        settings: settings,
        now: now,
      );
      expect(plan, hasLength(1));
      expect(plan.single.repeat, PlannedRepeat.daily);
      // 08:00 already passed today → first fire is tomorrow 08:00.
      expect(plan.single.firstAt, DateTime(2026, 8, 9, 8, 0));
      expect(plan.single.payload, 'routine:a');
    });

    test('weekly routine reminds only on its own days (the old daily-buzz bug)',
        () {
      final plan = planReminders(
        routines: [
          routine('t',
              time: '09:00',
              type: RecurrenceType.weekly,
              days: const [2]) // Tuesdays only
        ],
        events: const [],
        settings: settings,
        now: now,
      );
      expect(plan, hasLength(1));
      expect(plan.single.repeat, PlannedRepeat.weekly);
      // Next Tuesday after Saturday 2026-08-08 is 2026-08-11.
      expect(plan.single.firstAt, DateTime(2026, 8, 11, 9, 0));
    });

    test('weekdays routine spreads over Mon..Fri, never the weekend', () {
      final plan = planReminders(
        routines: [routine('w', time: '08:15', type: RecurrenceType.weekdays)],
        events: const [],
        settings: settings,
        now: now,
      );
      expect(plan, hasLength(5));
      expect(plan.every((p) => p.repeat == PlannedRepeat.weekly), isTrue);
      final weekdays = plan.map((p) => p.firstAt.weekday).toSet();
      expect(weekdays, {1, 2, 3, 4, 5}); // DateTime Mon..Fri
    });

    test('inactive or timeless routines get nothing', () {
      final plan = planReminders(
        routines: [
          routine('x', time: '08:00', active: false),
          routine('y'), // no time
        ],
        events: const [],
        settings: settings,
        now: now,
      );
      expect(plan, isEmpty);
    });
  });

  group('planReminders — plans (calendar events)', () {
    test('a timed plan gets one heads-up, lead minutes before', () {
      final plan = planReminders(
        routines: const [],
        events: [event('e1', '2026-08-08', '14:30')],
        settings: settings, // default 30 min before
        now: now,
      );
      expect(plan, hasLength(1));
      expect(plan.single.repeat, PlannedRepeat.none);
      expect(plan.single.firstAt, DateTime(2026, 8, 8, 14, 0));
      expect(plan.single.payload, 'event:e1:2026-08-08');
      expect(plan.single.body, contains('14:30'));
    });

    test('lead -1 turns plan reminders off; all-day and past plans skipped',
        () {
      final off = planReminders(
        routines: const [],
        events: [event('e1', '2026-08-08', '14:30')],
        settings: settings.copyWith(eventReminderMinutes: -1),
        now: now,
      );
      expect(off, isEmpty);

      final edge = planReminders(
        routines: const [],
        events: [
          event('past', '2026-08-08', '09:00'), // already gone
          event('allday', '2026-08-09', null, allDay: true),
          event('far', '2026-09-20', '10:00'), // beyond the horizon
        ],
        settings: settings,
        now: now,
      );
      expect(edge, isEmpty);
    });

    test('an answered plan needs no reminding', () {
      final plan = planReminders(
        routines: const [],
        events: [
          event('done', '2026-08-08', '14:30').copyWith(answer: 'done'),
          event('open', '2026-08-08', '16:00'),
        ],
        settings: settings,
        now: now,
      );
      expect(plan, hasLength(1));
      expect(plan.single.payload, 'event:open:2026-08-08');
    });

    test('plans are capped so routines always keep room', () {
      final many = [
        for (var i = 0; i < 40; i++)
          event('e$i', '2026-08-09', '12:00'),
      ];
      final plan = planReminders(
        routines: const [],
        events: many,
        settings: settings,
        now: now,
      );
      expect(plan, hasLength(kMaxEventReminders));
    });
  });

  group('planReminders — the person\'s switches', () {
    test('notifications off means silence', () {
      final plan = planReminders(
        routines: [routine('a', time: '08:00')],
        events: [event('e1', '2026-08-08', '14:30')],
        settings: settings.copyWith(notificationsEnabled: false),
        now: now,
      );
      expect(plan, isEmpty);
    });

    test('a caregiver device never buzzes about the other person\'s day', () {
      final plan = planReminders(
        routines: [routine('a', time: '08:00')],
        events: const [],
        settings: settings.copyWith(caregiverDevice: true),
        now: now,
      );
      expect(plan, isEmpty);
    });
  });

  group('reminderFingerprint', () {
    test('stable for irrelevant changes, moves for relevant ones', () {
      final routines = [routine('a', time: '08:00')];
      final events = [event('e1', '2026-08-08', '14:30')];
      final f1 = reminderFingerprint(
          routines: routines, events: events, settings: settings, now: now);
      final f2 = reminderFingerprint(
          routines: routines,
          events: events,
          settings: settings,
          now: now.add(const Duration(minutes: 5)));
      expect(f1, f2, reason: 'same day, same data — no reschedule needed');

      final f3 = reminderFingerprint(
          routines: [routine('a', time: '08:30')],
          events: events,
          settings: settings,
          now: now);
      expect(f1, isNot(f3), reason: 'a moved time must reschedule');

      final f4 = reminderFingerprint(
          routines: routines,
          events: events,
          settings: settings.copyWith(notificationColor: 'rose'),
          now: now);
      expect(f1, isNot(f4), reason: 'a new color must reschedule');
    });
  });

  group('routeForReminderPayload', () {
    test('routines go home, plans open their day', () {
      expect(routeForReminderPayload('routine:a'), '/');
      expect(routeForReminderPayload('event:e1:2026-08-08'),
          '/day?date=2026-08-08');
      expect(routeForReminderPayload(null), '/');
      expect(routeForReminderPayload('junk'), '/');
    });
  });

  group('AppSettings reminder fields', () {
    test('roundtrip via JSON keeps the choices', () {
      final s = settings.copyWith(
        reminderStyle: 'bright',
        notificationColor: 'sky',
        eventReminderMinutes: 10,
      );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.reminderStyle, 'bright');
      expect(back.notificationColor, 'sky');
      expect(back.eventReminderMinutes, 10);
    });

    test('old files without the fields get kind defaults', () {
      final back = AppSettings.fromJson(const {'id': 'singleton'});
      expect(back.reminderStyle, 'gentle');
      expect(back.notificationColor, 'auto');
      expect(back.eventReminderMinutes, 30);
    });
  });
}
