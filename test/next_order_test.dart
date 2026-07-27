import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/routine.dart';
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
}
