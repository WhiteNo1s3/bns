/// THE DAY STARTS WHEN YOU WAKE (owner, 2026-08-21: "push the entity of
/// the routine into whatever hour the user woke up").
///
/// Held here:
///  - the head of the shape is the first routine in OWL order (the 02:00
///    water never leads a 15:00 day);
///  - קמתי slides every routine of today by the same gap, late or early,
///    quarter-snapped, clamped before the border;
///  - answered rows and the person's own moves today do not move;
///  - waking exactly at the head, or a clockless day, moves nothing;
///  - the wake setting round-trips and reads only its own day;
///  - the door asks with the head hour and its two doors answer; answered
///    it is a quiet line with no doors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/wake_anchor.dart';
import 'package:bns/ui/widgets/wake_anchor_door.dart';

void main() {
  setUp(() => L.lang = 'he');

  final created = DateTime(2026, 8, 1);
  Routine r(String id, String? time,
          {Map<String, String> byDay = const {}}) =>
      Routine(
        id: id,
        title: 'R $id',
        recurrenceType: RecurrenceType.daily,
        time: time,
        timeByDay: byDay,
        createdAt: created,
        updatedAt: created,
      );
  final day = DateTime(2026, 8, 21);
  const key = '2026-08-21';

  // Ben's day: 15:00 → 05:00.
  final owl = [r('water', '02:00'), r('start', '15:00'), r('bag', '17:00'),
      r('tea', '16:00')];

  group('the head of the shape', () {
    test('is the earliest routine in OWL order, not clock order', () {
      expect(dayHeadTime(routines: owl, day: day, rolloverHour: 5), '15:00',
          reason: 'with a 05:00 border the 02:00 water closes the day');
    });
    test('in the midnight world the plain earliest leads', () {
      expect(
          dayHeadTime(
              routines: [r('a', '08:00'), r('b', '02:00')],
              day: day,
              rolloverHour: 0),
          '02:00');
    });
    test('a clockless day has no head', () {
      expect(dayHeadTime(routines: [r('x', null)], day: day, rolloverHour: 5),
          isNull);
    });
  });

  group('קמתי slides the shape, today only', () {
    test('a late wake: every routine follows by its own gap', () {
      final m = wakeAnchoredTimes(
          routines: owl, day: day, dayKey: key, wokeAt: '17:30',
          rolloverHour: 5);
      expect(m['start'], '17:30');
      expect(m['tea'], '18:30');
      expect(m['bag'], '19:30');
      expect(m['water'], '04:30', reason: 'the night slides with the day');
    });

    test('an early wake: the day comes forward', () {
      final m = wakeAnchoredTimes(
          routines: owl, day: day, dayKey: key, wokeAt: '13:00',
          rolloverHour: 5);
      expect(m['start'], '13:00');
      expect(m['tea'], '14:00');
      expect(m['bag'], '15:00');
      expect(m['water'], '00:00');
    });

    test('the wake hour snaps to a quarter — no 17:38', () {
      final m = wakeAnchoredTimes(
          routines: owl, day: day, dayKey: key, wokeAt: '17:38',
          rolloverHour: 5);
      expect(m['start'], '17:45');
      expect(m['tea'], '18:45');
    });

    test('nothing passes the border — the night clamps to the last quarter',
        () {
      final late = [r('start', '15:00'), r('pills', '03:00'),
          r('last', '04:45')];
      final m = wakeAnchoredTimes(
          routines: late, day: day, dayKey: key, wokeAt: '17:30',
          rolloverHour: 5);
      expect(m['pills'], '04:45', reason: '03:00 + 2:30 would cross 05:00');
      expect(m.containsKey('last'), isFalse,
          reason: 'already at the last quarter — nothing to write');
    });

    test('answered rows stay where they were answered', () {
      final m = wakeAnchoredTimes(
          routines: owl, day: day, dayKey: key, wokeAt: '17:30',
          rolloverHour: 5, answeredIds: {'start'});
      expect(m.containsKey('start'), isFalse);
      expect(m['tea'], '18:30', reason: 'the head still anchors the shift');
    });

    test('a row the person moved today keeps their move', () {
      final mine = [r('start', '15:00'), r('tea', '16:00', byDay: {key: '16:30'})];
      final m = wakeAnchoredTimes(
          routines: mine, day: day, dayKey: key, wokeAt: '17:30',
          rolloverHour: 5);
      expect(m['start'], '17:30');
      expect(m.containsKey('tea'), isFalse);
    });

    test('waking exactly at the head moves nothing', () {
      expect(
          wakeAnchoredTimes(
              routines: owl, day: day, dayKey: key, wokeAt: '15:00',
              rolloverHour: 5),
          isEmpty);
    });

    test('a clockless day moves nothing', () {
      expect(
          wakeAnchoredTimes(
              routines: [r('x', null)], day: day, dayKey: key,
              wokeAt: '17:30', rolloverHour: 5),
          isEmpty);
    });
  });

  group('the wake setting', () {
    test('round-trips through AppSettings json; old files read as unset', () {
      const s = AppSettings(wokeAt: '2026-08-21 17:45');
      expect(AppSettings.fromJson(s.toJson()).wokeAt, '2026-08-21 17:45');
      expect(AppSettings.fromJson(const {}).wokeAt, '');
    });
    test('wokeAtFor reads only its own day', () {
      expect(wokeAtFor('2026-08-21 17:45', key), '17:45');
      expect(wokeAtFor('2026-08-20 17:45', key), isNull,
          reason: 'yesterday\'s wake is not today\'s');
      expect(wokeAtFor('', key), isNull);
      expect(wokeAtFor('garbage', key), isNull);
    });
    test('a quarter snap keeps its hour', () {
      expect(snapToQuarterHhmm('17:38'), '17:45');
      expect(snapToQuarterHhmm('17:07'), '17:00');
      expect(snapToQuarterHhmm('17:08'), '17:15');
      expect(snapToQuarterHhmm('23:53'), '00:00');
    });
  });

  group('the door', () {
    testWidgets('asks with the head hour; קמתי and עוד לא קמתי answer',
        (tester) async {
      var up = 0, notYet = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WakeAnchorDoor(
            headHhmm: '08:00',
            anchoredHhmm: null,
            onUp: () => up++,
            onNotYet: () => notYet++,
          ),
        ),
      ));
      expect(find.text('היום מתחיל ב-08:00.'), findsOneWidget);
      expect(find.text('קמתי'), findsOneWidget);
      expect(find.text('עוד לא קמתי'), findsOneWidget);

      await tester.tap(find.text('קמתי'));
      await tester.pump();
      expect(up, 1);
      await tester.tap(find.text('עוד לא קמתי'));
      await tester.pump();
      expect(notYet, 1);
    });

    testWidgets('answered, it is a quiet line with no doors', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WakeAnchorDoor(
            headHhmm: '08:00',
            anchoredHhmm: '17:45',
            onUp: () {},
            onNotYet: () {},
          ),
        ),
      ));
      expect(find.text('קמת ב-17:45 — הרשימה זזה לשם. רק להיום.'),
          findsOneWidget);
      expect(find.text('קמתי'), findsNothing);
      expect(find.text('עוד לא קמתי'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
