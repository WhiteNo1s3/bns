import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/day_items.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/reminder_plan.dart';

void main() {
  L.lang = 'en';

  group('logicalDateOf — the movable border', () {
    test('border 04:00 — 01:30 still belongs to yesterday', () {
      expect(logicalDateOf(DateTime(2026, 8, 10, 1, 30), 4),
          DateTime(2026, 8, 9));
      expect(logicalDateOf(DateTime(2026, 8, 10, 3, 59), 4),
          DateTime(2026, 8, 9));
      // At the border the new day begins.
      expect(logicalDateOf(DateTime(2026, 8, 10, 4, 0), 4),
          DateTime(2026, 8, 10));
      expect(logicalDateOf(DateTime(2026, 8, 10, 23, 59), 4),
          DateTime(2026, 8, 10));
    });

    test('border 0 = the old midnight world, exactly', () {
      expect(logicalDateOf(DateTime(2026, 8, 10, 0, 0), 0),
          DateTime(2026, 8, 10));
      expect(logicalDateOf(DateTime(2026, 8, 10, 23, 59), 0),
          DateTime(2026, 8, 10));
    });

    test('month border folds correctly (Aug 1st, 01:00 → July 31)', () {
      expect(logicalDateOf(DateTime(2026, 8, 1, 1, 0), 4),
          DateTime(2026, 7, 31));
    });

    test('yesterday’s note does not belong on today’s tiles', () {
      const today = '2026-08-14';
      expect(
        belongsToLogicalDay(DateTime(2026, 8, 13, 15, 0), today, 0),
        isFalse,
      );
      expect(
        belongsToLogicalDay(DateTime(2026, 8, 14, 9, 0), today, 0),
        isTrue,
      );
    });
  });

  group('owlMinutesOf — the night sorts after the evening', () {
    test('with border 04:00, 02:00 pills come AFTER 23:00 wind-down', () {
      final evening = owlMinutesOf(23, 0, 4);
      final pills = owlMinutesOf(2, 0, 4);
      final morning = owlMinutesOf(8, 0, 4);
      expect(morning < evening, isTrue);
      expect(evening < pills, isTrue, reason: 'the night belongs to tonight');
    });

    test('border 0 keeps plain clock order', () {
      expect(owlMinutesOf(2, 0, 0) < owlMinutesOf(23, 0, 0), isTrue);
    });
  });

  group('actualMomentOf — logical date + small hour = that night', () {
    test('logical Aug 9 at 02:00 with border 4 happens Aug 10, 02:00', () {
      expect(actualMomentOf(DateTime(2026, 8, 9), 2, 0, 4),
          DateTime(2026, 8, 10, 2, 0));
    });
    test('daytime hours stay on their own date', () {
      expect(actualMomentOf(DateTime(2026, 8, 9), 14, 0, 4),
          DateTime(2026, 8, 9, 14, 0));
    });
  });

  group('weaveDayList honors the border', () {
    Routine r(String id, String? time) => Routine(
          id: id,
          title: 'R $id',
          recurrenceType: RecurrenceType.daily,
          time: time,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        );
    String ids(List<Object> l) =>
        l.map((e) => (e as Routine).id).join(',');

    test('02:00 pills close the day, after the evening', () {
      final woven = weaveDayList(
        routines: [r('pills', '02:00'), r('morning', '08:00'), r('wind', '23:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        nextFirst: false,
        now: DateTime(2026, 8, 9, 12, 0),
        rolloverHour: 4,
      );
      expect(ids(woven), 'morning,wind,pills');
    });

    test('"what\'s next" at 01:00 knows the pills are the nearest thing', () {
      final woven = weaveDayList(
        routines: [r('pills', '02:00'), r('morning', '08:00'), r('wind', '23:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        nextFirst: true,
        now: DateTime(2026, 8, 10, 1, 0), // logical Aug 9 night
        rolloverHour: 4,
      );
      // pills (02:00) are upcoming; morning+wind already passed today.
      expect(ids(woven).startsWith('pills'), isTrue);
    });
  });

  group('planReminders honors the border', () {
    const created = '2026-08-01';
    final now = DateTime(2026, 8, 8, 10, 0); // Saturday

    Routine weekly(String id, String time, List<int> days) => Routine(
          id: id,
          title: 'R $id',
          recurrenceType: RecurrenceType.weekly,
          daysOfWeek: days,
          time: time,
          createdAt: DateTime.parse(created),
          updatedAt: DateTime.parse(created),
        );

    test('"Tuesday night pills at 02:00" fire calendar WEDNESDAY 02:00', () {
      final plan = planReminders(
        routines: [weekly('t', '02:00', const [2])], // Tuesday, dow 0=Sun
        events: const [],
        settings: const AppSettings().copyWith(dayRolloverHour: 4),
        now: now,
      );
      // Next Tuesday is 2026-08-11 → its night at 02:00 is Wed 2026-08-12.
      expect(plan.single.firstAt, DateTime(2026, 8, 12, 2, 0));
    });

    test('without owl time the same routine fires Tuesday 02:00 (dawn)', () {
      final plan = planReminders(
        routines: [weekly('t', '02:00', const [2])],
        events: const [],
        settings: const AppSettings(),
        now: now,
      );
      expect(plan.single.firstAt, DateTime(2026, 8, 11, 2, 0));
    });

    test('a plan for tonight at 02:00 reminds that NIGHT, not this morning',
        () {
      final e = CalendarEvent(
        id: 'late',
        title: 'Night thing',
        date: '2026-08-08', // the person's "today"
        time: '02:00',
        createdAt: DateTime.parse(created),
        updatedAt: DateTime.parse(created),
      );
      final owl = planReminders(
        routines: const [],
        events: [e],
        settings: const AppSettings().copyWith(dayRolloverHour: 4),
        now: now,
      );
      // Actual moment: Aug 9 02:00; heads-up 30 min before, still ahead.
      expect(owl.single.firstAt, DateTime(2026, 8, 9, 1, 30));

      final midnightWorld = planReminders(
        routines: const [],
        events: [e],
        settings: const AppSettings(),
        now: now,
      );
      // In the old world Aug 8 02:00 already passed — nothing to remind.
      expect(midnightWorld, isEmpty);
    });

    test('the border is part of the reminder fingerprint', () {
      final f0 = reminderFingerprint(
          routines: const [],
          events: const [],
          settings: const AppSettings(),
          now: now);
      final f4 = reminderFingerprint(
          routines: const [],
          events: const [],
          settings: const AppSettings().copyWith(dayRolloverHour: 4),
          now: now);
      expect(f0, isNot(f4));
    });
  });

  group('AppSettings.dayRolloverHour', () {
    test('roundtrips and clamps to 0..6', () {
      final s = const AppSettings().copyWith(dayRolloverHour: 4);
      expect(AppSettings.fromJson(s.toJson()).dayRolloverHour, 4);
      expect(
          AppSettings.fromJson(const {'id': 'singleton', 'dayRolloverHour': 9})
              .dayRolloverHour,
          6);
      expect(AppSettings.fromJson(const {'id': 'singleton'}).dayRolloverHour,
          0);
    });
  });

  group('AppSettings.dayStartHour', () {
    test('roundtrips, clamps, and reads a string 15 as 15 not 0', () {
      final s = const AppSettings().copyWith(dayStartHour: 15);
      expect(AppSettings.fromJson(s.toJson()).dayStartHour, 15);
      expect(
          AppSettings.fromJson(const {'id': 'singleton', 'dayStartHour': 30})
              .dayStartHour,
          23);
      expect(AppSettings.fromJson(const {'id': 'singleton'}).dayStartHour, 0);
      expect(
          AppSettings.fromJson(const {'id': 'singleton', 'dayStartHour': '15'})
              .dayStartHour,
          15,
          reason: 'a written "15" must not become midnight after reload');
    });
  });

  group('adoptPersonDayHour — 0 is unset, a helper cannot midnight 15', () {
    test('a set 15 survives a Care / default 0', () {
      expect(
        adoptPersonDayHour(incoming: 0, local: 15, incomingIsHelper: true),
        15,
      );
      expect(adoptPersonDayHour(incoming: 0, local: 15), 15);
    });
    test('Care learns 15 from the person', () {
      expect(adoptPersonDayHour(incoming: 15, local: 0), 15);
    });
    test('a set incoming hour wins between own devices', () {
      expect(adoptPersonDayHour(incoming: 12, local: 15), 12);
    });
    test('both unset stay midnight', () {
      expect(adoptPersonDayHour(incoming: 0, local: 0), 0);
    });
  });

  group('person-day hole — 15:00 → 05:00', () {
    final night = DateTime(2026, 8, 17, 21, 32);
    test('07:30 is outside tonight after the day has started', () {
      expect(
        inPersonDayWindow(
          hour: 7,
          minute: 30,
          now: night,
          startHour: 15,
          rolloverHour: 5,
        ),
        isFalse,
      );
      expect(
        isNextMorningSlot(
          usualHhmm: '07:30',
          todayHhmm: '21:45',
          now: night,
          startHour: 15,
          rolloverHour: 5,
        ),
        isTrue,
        reason: 'leftover 21:45 on a morning stack is still next morning',
      );
    });

    test('21:45 and 02:00 belong to tonight', () {
      expect(
        inPersonDayWindow(
          hour: 21,
          minute: 45,
          now: night,
          startHour: 15,
          rolloverHour: 5,
        ),
        isTrue,
      );
      expect(
        inPersonDayWindow(
          hour: 2,
          minute: 0,
          now: night,
          startHour: 15,
          rolloverHour: 5,
        ),
        isTrue,
      );
    });

    test('04:00 owl is still this day; 07:30 is not', () {
      final owl = DateTime(2026, 8, 18, 3, 30);
      expect(
        inPersonDayWindow(
          hour: 4,
          minute: 0,
          now: owl,
          startHour: 15,
          rolloverHour: 5,
        ),
        isTrue,
      );
      expect(
        isNextMorningSlot(
          usualHhmm: '07:30',
          now: owl,
          startHour: 15,
          rolloverHour: 5,
        ),
        isTrue,
      );
    });

    test('before the day starts, 07:30 is this calendar morning', () {
      final afternoon = DateTime(2026, 8, 17, 14, 0);
      expect(personDayHasStarted(afternoon, 15, 5), isFalse);
      expect(
        isNextMorningSlot(
          usualHhmm: '07:30',
          now: afternoon,
          startHour: 15,
          rolloverHour: 5,
        ),
        isFalse,
      );
    });

    test('unset startHour 0 at 23:28 — leftover 21:45 is still next morning',
        () {
      // Lived L1 S23: dayStartHour showed 0, a8b1205's hole never fired.
      final late = DateTime(2026, 8, 17, 23, 28);
      expect(eveningHasBegun(late, 5), isTrue);
      expect(nextHoleStartHour(0, late, 5), 15,
          reason: 'virtual hole only — must not persist dayStartHour');
      expect(
        isNextMorningSlot(
          usualHhmm: '07:45',
          todayHhmm: '21:45',
          now: late,
          startHour: 0,
          rolloverHour: 5,
        ),
        isTrue,
        reason: 'unset 0 must not let leftover 21:45 steal הבא',
      );
      expect(
        isNextMorningSlot(
          usualHhmm: '04:00',
          now: late,
          startHour: 0,
          rolloverHour: 5,
        ),
        isFalse,
        reason: '04:00 owl is still tonight when start is unset',
      );
    });

    test('unset startHour 0 before evening — 07:30 may still be next', () {
      final morning = DateTime(2026, 8, 17, 10, 0);
      expect(eveningHasBegun(morning, 5), isFalse);
      expect(
        isNextMorningSlot(
          usualHhmm: '07:30',
          now: morning,
          startHour: 0,
          rolloverHour: 5,
        ),
        isFalse,
      );
    });
  });
}
