import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/day_items.dart';
import 'package:bns/core/models/models.dart';

void main() {
  final created = DateTime(2026, 8, 1);

  Routine r(String id, String? time) => Routine(
        id: id,
        title: 'R $id',
        recurrenceType: RecurrenceType.daily,
        time: time,
        createdAt: created,
        updatedAt: created,
      );

  CalendarEvent p(String id, String? time,
          {String? answer, bool allDay = false}) =>
      CalendarEvent(
        id: id,
        title: 'P $id',
        date: '2026-08-09',
        time: time,
        isAllDay: allDay,
        answer: answer,
        createdAt: created,
        updatedAt: created,
      );

  String ids(List<Object> l) => l
      .map((e) => e is Routine ? e.id : (e as CalendarEvent).id)
      .join(',');

  test('plans weave into the day by the clock; timeless close the list', () {
    final woven = weaveDayList(
      routines: [r('a', '08:00'), r('c', '20:00'), r('t', null)],
      plans: [p('doc', '14:30'), p('allday', null)],
      doneRoutineIds: const {},
      skippedRoutineIds: const {},
      nextFirst: false,
      now: DateTime(2026, 8, 9, 10, 0),
    );
    expect(ids(woven), 'a,doc,c,t,allday');
  });

  test(
      'THE DAY STAYS STEADY (owner, 2026-08-14) — answering never moves a '
      'tile: a ✓ shows in place, the clock order never reshuffles', () {
    final before = weaveDayList(
      routines: [r('a', '08:00'), r('b', '12:00')],
      plans: [p('doc', '09:00'), p('err', '15:00')],
      doneRoutineIds: const {},
      skippedRoutineIds: const {},
      nextFirst: false,
      now: DateTime(2026, 8, 9, 10, 0),
    );
    final after = weaveDayList(
      routines: [r('a', '08:00'), r('b', '12:00')],
      plans: [p('doc', '09:00', answer: 'done'), p('err', '15:00')],
      doneRoutineIds: {'a'},
      skippedRoutineIds: const {},
      nextFirst: false,
      now: DateTime(2026, 8, 9, 10, 0),
    );
    // Same clock order before and after answering — nothing jumped.
    expect(ids(before), 'a,doc,b,err');
    expect(ids(after), ids(before));
  });

  test('"what\'s next" ranks upcoming plans with upcoming routines', () {
    final woven = weaveDayList(
      routines: [r('morning', '08:00'), r('evening', '18:30')],
      plans: [p('doc', '14:30')],
      doneRoutineIds: const {},
      skippedRoutineIds: const {},
      nextFirst: true,
      now: DateTime(2026, 8, 9, 13, 0), // 13:00 — doc is nearest
    );
    expect(ids(woven), 'doc,evening,morning');
  });

  test('CalendarEvent answer roundtrips through JSON', () {
    final e = p('doc', '14:30').copyWith(
        answer: 'skipped',
        answerReason: 'The bus never came',
        answerAt: DateTime(2026, 8, 9, 15, 0));
    final back = CalendarEvent.fromJson(e.toJson());
    expect(back.isSkipped, isTrue);
    expect(back.answerReason, 'The bus never came');
    expect(back.answerAt, DateTime(2026, 8, 9, 15, 0));
    // Taking the answer back clears everything — the plan is simply open.
    final reopened = back.copyWith(answer: null, answerReason: null, answerAt: null);
    expect(reopened.isAnswered, isFalse);
    expect(reopened.answerReason, isNull);
  });

  test('at 21:32, a 22:00 plan is Next — not 07:30 morning meds', () {
    final now = DateTime(2026, 8, 17, 21, 32);
    final open = openDayItemsInNextOrder(
      routines: [r('meds', '07:45'), r('breakfast', '07:30')],
      plans: [p('evening', '22:00')],
      doneRoutineIds: const {},
      skippedRoutineIds: const {},
      now: now,
      rolloverHour: 5,
      startHour: 15,
    );
    expect(ids(open), 'evening,breakfast,meds',
        reason: 'plans-in-Next walk the person-day; morning stays visible');
    expect(open.first, isA<CalendarEvent>());
  });
}
