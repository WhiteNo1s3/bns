import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/routine.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/ui/widgets/next_hero_card.dart';

void main() {
  Routine r(String id, String? time, String title) => Routine(
        id: id,
        title: title,
        recurrenceType: RecurrenceType.daily,
        time: time,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  test('openRoutinesInNextOrder picks upcoming nearest, skips done/skipped',
      () {
    final now = DateTime(2026, 7, 27, 18, 18); // 18:18
    final list = [
      r('a', '09:00', 'Morning'),
      r('b', '18:30', 'Evening meds'),
      r('c', '20:00', 'Wind down'),
      r('d', null, 'Whenever'),
    ];
    final open = openRoutinesInNextOrder(
      todays: list,
      doneIds: {'a'},
      skippedIds: {},
      now: now,
    );
    // a done; b 18:30 next; then c; then timeless
    expect(open.map((x) => x.id).toList(), ['b', 'c', 'd']);
  });

  test('skipped items are not next', () {
    final now = DateTime(2026, 7, 27, 10, 0);
    final list = [
      r('a', '09:00', 'A'),
      r('b', '11:00', 'B'),
    ];
    final open = openRoutinesInNextOrder(
      todays: list,
      doneIds: {},
      skippedIds: {'a'},
      now: now,
    );
    expect(open.single.id, 'b');
  });

  test('at 21:32 in a 15:00–05:00 day, evening is הבא — not morning meds',
      () {
    // Lived 2026-08-17 ~21:32 IDT: הבא was still תרופות הבוקר 21:45
    // part 1/3, labeled too late, while breakfast 07:30 through evening
    // stayed open. Night and the next-goal rank were lying.
    final now = DateTime(2026, 8, 17, 21, 32);
    final morning = Routine(
      id: 'meds',
      title: 'תרופות הבוקר',
      recurrenceType: RecurrenceType.daily,
      time: '07:45',
      timeByDay: const {'2026-08-17': '21:45'},
      steps: const [
        RoutineStep(title: 'drink water before the pill'),
        RoutineStep(title: 'the pill'),
        RoutineStep(title: 'sit a minute'),
      ],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    final breakfast = r('breakfast', '07:30', 'ארוחת בוקר');
    final evening = r('evening', '20:00', 'משהו קל לאכול');
    final night = r('night', '22:00', 'הכנה לשינה');
    final open = openRoutinesInNextOrder(
      todays: [morning, breakfast, evening, night],
      doneIds: {},
      skippedIds: {},
      now: now,
      dayKey: logicalDayKey(now, 5),
      rolloverHour: 5,
      startHour: 15,
    );
    expect(open.map((x) => x.id).toList(),
        ['night', 'evening', 'breakfast', 'meds'],
        reason: '22:00 is still ahead tonight; 20:00 is earlier today; '
            'the morning stack stays visible and is not הבא');
    expect(open.first.title, 'הכנה לשינה');
    expect(open.map((x) => x.id), containsAll(['meds', 'breakfast']));
  });

  test('missed morning stays visible when only evening is left — not as הבא',
      () {
    final now = DateTime(2026, 8, 17, 21, 32);
    final morning = r('meds', '07:45', 'תרופות הבוקר');
    final evening = r('evening', '20:00', 'כוס מים');
    final open = openRoutinesInNextOrder(
      todays: [morning, evening],
      doneIds: {},
      skippedIds: {},
      now: now,
      rolloverHour: 5,
      startHour: 15,
    );
    expect(open.first.id, 'evening',
        reason: '20:00 is tonight, already passed, still the real next');
    expect(open.map((x) => x.id), contains('meds'));
  });

  test('04:00 owl is still this day — 07:30 is not הבא', () {
    final now = DateTime(2026, 8, 18, 3, 30);
    final owl = r('owl', '04:00', 'כדור הלילה');
    final morning = r('breakfast', '07:30', 'ארוחת בוקר');
    final open = openRoutinesInNextOrder(
      todays: [morning, owl],
      doneIds: {},
      skippedIds: {},
      now: now,
      rolloverHour: 5,
      startHour: 15,
    );
    expect(open.first.id, 'owl',
        reason: 'the person-day has not rolled; 04:00 is still tonight');
    expect(open.map((x) => x.id), contains('breakfast'));
  });

  void lived2328(int startHour) {
    // Lived 2026-08-17 23:28 IDT on S23 0.11.0 lastUpdate 22:07 (a8b1205
    // was IN the APK). הבא was still 21:45 morning stack; after skip it
    // jumped backward to 21:30 screen-off while evening + family stayed open.
    final now = DateTime(2026, 8, 17, 23, 28);
    final morning = Routine(
      id: 'meds',
      title: 'תרופות הבוקר',
      recurrenceType: RecurrenceType.daily,
      time: '07:45',
      timeByDay: const {'2026-08-17': '21:45'},
      steps: const [
        RoutineStep(title: 'לשתות כוס מים'),
        RoutineStep(title: 'the pill'),
        RoutineStep(title: 'sit a minute'),
      ],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    final evening = r('evening', '20:00', 'תרופות הערב');
    final family = r('family', '22:00', 'שיחה משפחתית');
    final screen = r('screen', '21:30', 'הכנה לשינה / לכבות מסכים');
    final todays = [morning, evening, family, screen];
    final open = openRoutinesInNextOrder(
      todays: todays,
      doneIds: {},
      skippedIds: {},
      now: now,
      dayKey: logicalDayKey(now, 5),
      rolloverHour: 5,
      startHour: startHour,
    );
    expect(open.first.id, 'evening',
        reason: 'startHour=$startHour: leftover 21:45 morning is not הבא '
            'while evening is open');
    expect(open.map((x) => x.id).toList(),
        ['evening', 'screen', 'family', 'meds'],
        reason: 'person-day walks forward: evening, then 21:30, then 22:00; '
            'morning leftover last');

    final afterSkip = openRoutinesInNextOrder(
      todays: todays,
      doneIds: {},
      skippedIds: {'meds'},
      now: now,
      dayKey: logicalDayKey(now, 5),
      rolloverHour: 5,
      startHour: startHour,
    );
    expect(afterSkip.first.id, 'evening',
        reason: 'startHour=$startHour: after skip, הבא goes forward to '
            'evening — not backward to 21:30');
    expect(afterSkip.map((x) => x.id), isNot(contains('meds')));
    expect(afterSkip.map((x) => x.id), containsAll(['evening', 'family']));
  }

  test('23:28 leftover 21:45 morning stack — הבא is evening (start 15)',
      () => lived2328(15));

  test('23:28 leftover 21:45 morning stack — הבא is evening (start unset 0)',
      () => lived2328(0));
}
