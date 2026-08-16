import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/day_items.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/later_today.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/reminder_plan.dart';

void main() {
  L.lang = 'en';
  final created = DateTime(2026, 8, 1);

  Routine r(String id, String? time) => Routine(
        id: id,
        title: 'R $id',
        recurrenceType: RecurrenceType.daily,
        time: time,
        createdAt: created,
        updatedAt: created,
      );

  CalendarEvent p(String id, String? time, {String date = '2026-08-09'}) =>
      CalendarEvent(
        id: id,
        title: 'P $id',
        date: date,
        time: time,
        createdAt: created,
        updatedAt: created,
      );

  String ids(List<Object> l) =>
      l.map((e) => e is Routine ? e.id : (e as CalendarEvent).id).join(',');

  group('laterTodaySlots', () {
    test('from 15:00 the first later slot is 15:15 and 17:30 is offered', () {
      final slots = laterTodaySlots(now: DateTime(2026, 8, 9, 15, 0));
      expect(slots.first, '15:15');
      expect(slots, contains('17:30'));
      expect(slots, isNot(contains('15:00')));
      expect(slots.last, '23:45');
    });

    test('cannot pick a time already past', () {
      final now = DateTime(2026, 8, 9, 16, 0);
      final slots = laterTodaySlots(now: now);
      expect(slots, isNot(contains('15:00')));
      expect(slots, isNot(contains('15:45')));
      expect(slots, isNot(contains('16:00')));
      expect(slots.first, '16:15');
      expect(isLaterTodaySlot('15:00', now: now), isFalse);
      expect(isLaterTodaySlot('17:30', now: now), isTrue);
    });

    test('seconds snap the next quarter up — 15:00:01 + 15min is 15:30', () {
      final slots = laterTodaySlots(now: DateTime(2026, 8, 9, 15, 0, 1));
      expect(slots.first, '15:30');
    });

    test('late night with midnight border: nothing later left today', () {
      expect(laterTodaySlots(now: DateTime(2026, 8, 9, 23, 50)), isEmpty);
    });

    test('owl-time night is still tonight — 02:00 is offered, 04:00 is not',
        () {
      final evening = laterTodaySlots(
        now: DateTime(2026, 8, 9, 22, 0),
        rolloverHour: 4,
      );
      expect(evening, contains('23:45'));
      expect(evening, contains('00:00'));
      expect(evening, contains('02:00'));
      expect(evening, contains('03:45'));
      expect(evening, isNot(contains('04:00')));

      final afterMidnight = laterTodaySlots(
        now: DateTime(2026, 8, 10, 1, 30),
        rolloverHour: 4,
      );
      expect(afterMidnight, contains('02:00'));
      expect(afterMidnight, contains('03:45'));
      expect(afterMidnight, isNot(contains('04:00')));
      expect(afterMidnight, isNot(contains('01:30')));
    });
  });

  group('postpone moves Next / Coming up', () {
    test('15:00 pills → 17:30: Next becomes the 16:00 walk', () {
      final now = DateTime(2026, 8, 9, 14, 50);
      final before = openDayItemsInNextOrder(
        routines: [r('pills', '15:00'), r('walk', '16:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
      );
      expect(ids(before), 'pills,walk');
      expect(dayItemTime(before.first), '15:00');

      expect(isLaterTodaySlot('17:30', now: now), isTrue);
      final after = openDayItemsInNextOrder(
        routines: [r('pills', '17:30'), r('walk', '16:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
      );
      expect(ids(after), 'walk,pills');
      expect(dayItemTime(after.first), '16:00');
      expect(dayItemTime(after[1]), '17:30');
    });

    test('plan postpone 15:00 → 17:30 moves Next the same way', () {
      final now = DateTime(2026, 8, 9, 14, 50);
      final before = openDayItemsInNextOrder(
        routines: [r('walk', '16:00')],
        plans: [p('doc', '15:00')],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
      );
      expect(ids(before), 'doc,walk');
      expect(before.first, isA<CalendarEvent>());

      final after = openDayItemsInNextOrder(
        routines: [r('walk', '16:00')],
        plans: [p('doc', '17:30')],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
      );
      expect(ids(after), 'walk,doc');
      expect(dayItemTime(after.first), '16:00');
      expect((after[1] as CalendarEvent).time, '17:30');
    });

    test('postponed 02:00 still belongs to tonight when the border is set', () {
      final now = DateTime(2026, 8, 9, 22, 0);
      expect(isLaterTodaySlot('02:00', now: now, rolloverHour: 4), isTrue);

      final woven = weaveDayList(
        routines: [r('pills', '02:00'), r('wind', '23:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        nextFirst: false,
        now: now,
        rolloverHour: 4,
      );
      expect(ids(woven), 'wind,pills');

      final open = openDayItemsInNextOrder(
        routines: [r('pills', '02:00'), r('wind', '23:00')],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
        rolloverHour: 4,
      );
      // 23:00 is nearer; 02:00 is still tonight and still coming.
      expect(ids(open), 'wind,pills');
      expect(owlMinutesOf(2, 0, 4) > owlMinutesOf(23, 0, 4), isTrue);
    });
  });

  group('reminders follow the new clock', () {
    const settings = AppSettings();
    final now = DateTime(2026, 8, 9, 14, 50);

    test('routine fingerprint and firstAt move 15:00 → 17:30', () {
      final beforeR = [r('pills', '15:00')];
      final afterR = [r('pills', '17:30')];
      expect(
        reminderFingerprint(
            routines: beforeR, events: const [], settings: settings, now: now),
        isNot(reminderFingerprint(
            routines: afterR, events: const [], settings: settings, now: now)),
      );
      final planned = planReminders(
        routines: afterR,
        events: const [],
        settings: settings,
        now: now,
      );
      expect(planned.single.firstAt, DateTime(2026, 8, 9, 17, 30));
    });

    test('plan fingerprint and firstAt move 15:00 → 17:30', () {
      final beforeE = [p('doc', '15:00')];
      final afterE = [p('doc', '17:30')];
      expect(
        reminderFingerprint(
            routines: const [], events: beforeE, settings: settings, now: now),
        isNot(reminderFingerprint(
            routines: const [], events: afterE, settings: settings, now: now)),
      );
      final planned = planReminders(
        routines: const [],
        events: afterE,
        settings: settings, // 30 min lead
        now: now,
      );
      expect(planned.single.firstAt, DateTime(2026, 8, 9, 17, 0));
      expect(planned.single.body, contains('17:30'));
    });
  });

  group('today-only postpone — usual time comes back tomorrow', () {
    test('15:00 → 17:30 today: Next is 17:30; tomorrow logical day is 15:00',
        () {
      final todayNow = DateTime(2026, 8, 9, 16, 0);
      final todayKey = logicalDayKey(todayNow, 0);
      final pills = Routine(
        id: 'pills',
        title: 'R pills',
        recurrenceType: RecurrenceType.daily,
        time: '15:00',
        timeByDay: {todayKey: '17:30'},
        createdAt: created,
        updatedAt: created,
      );
      expect(pills.time, '15:00');
      expect(pills.timeOn(todayKey), '17:30');

      final todayNext = openDayItemsInNextOrder(
        routines: [pills],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: todayNow,
      );
      expect(dayItemTime(todayNext.single, dayKey: todayKey), '17:30');

      final tomorrowNow = DateTime(2026, 8, 10, 16, 0);
      final tomorrowKey = logicalDayKey(tomorrowNow, 0);
      expect(pills.timeOn(tomorrowKey), '15:00');
      final tomorrowNext = openDayItemsInNextOrder(
        routines: [pills],
        plans: const [],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: tomorrowNow,
      );
      expect(dayItemTime(tomorrowNext.single, now: tomorrowNow), '15:00');
    });

    test('plan postpone still updates that plan\'s time', () {
      final now = DateTime(2026, 8, 9, 14, 50);
      final plan = p('doc', '15:00').copyWith(time: '17:30');
      expect(plan.time, '17:30');
      final after = openDayItemsInNextOrder(
        routines: [r('walk', '16:00')],
        plans: [plan],
        doneRoutineIds: const {},
        skippedRoutineIds: const {},
        now: now,
      );
      expect(dayItemTime(after.first), '16:00');
      expect((after[1] as CalendarEvent).time, '17:30');
    });

    test('override rides JSON and the reminder fingerprint', () {
      final todayKey = '2026-08-09';
      final pills = Routine(
        id: 'pills',
        title: 'R pills',
        recurrenceType: RecurrenceType.daily,
        time: '15:00',
        timeByDay: {todayKey: '17:30'},
        createdAt: created,
        updatedAt: created,
      );
      final back = Routine.fromJson(pills.toJson());
      expect(back.time, '15:00');
      expect(back.timeOn(todayKey), '17:30');
      expect(back.timeByDay[todayKey], '17:30');

      const settings = AppSettings();
      final now = DateTime(2026, 8, 9, 16, 0);
      final usual = [r('pills', '15:00')];
      expect(
        reminderFingerprint(
            routines: usual, events: const [], settings: settings, now: now),
        isNot(reminderFingerprint(
            routines: [pills],
            events: const [],
            settings: settings,
            now: now)),
      );
      final planned = planReminders(
        routines: [pills],
        events: const [],
        settings: settings,
        now: now,
      );
      final firsts = planned.map((x) => x.firstAt).toList()..sort();
      expect(firsts, contains(DateTime(2026, 8, 9, 17, 30)));
      expect(firsts, contains(DateTime(2026, 8, 10, 15, 0)));
    });
  });

  group('later-today follows the person-day entity 15:00 → 05:00', () {
    test('at 16:00 includes 17:30 and 02:00, not 06:00', () {
      final slots = laterTodaySlots(
        now: DateTime(2026, 8, 9, 16, 0),
        rolloverHour: 5,
        startHour: 15,
      );
      expect(slots, contains('17:30'));
      expect(slots, contains('02:00'));
      expect(slots, isNot(contains('06:00')));
      expect(slots, isNot(contains('16:00')));
    });

    test('at 04:00 can include 04:30 but not 06:00', () {
      final slots = laterTodaySlots(
        now: DateTime(2026, 8, 10, 4, 0),
        rolloverHour: 5,
        startHour: 15,
      );
      expect(slots, contains('04:30'));
      expect(slots, isNot(contains('06:00')));
      expect(slots, isNot(contains('05:00')));
    });
  });
}
