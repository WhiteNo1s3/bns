/// WHAT DO WE TAKE — and who gets to answer.
///
/// Owner design, 2026-08-15, from rehabilitation at Shiba: a person who
/// cannot gather anything is still asked "did we take X?", and answering
/// is the part they play. These tests hold the data side of that promise:
/// an answer is a moment in time (not a bare flag), "not yet" is a state
/// and never a failure, taking an answer back is always possible, and a
/// plan written before gather lists existed still opens.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/calendar_event.dart';

void main() {
  CalendarEvent doctor({List<GatherItem> gather = const []}) => CalendarEvent(
        id: 'doc',
        title: 'רופא במרפאה',
        date: '2026-08-16',
        time: '10:00',
        gather: gather,
        createdAt: DateTime(2026, 8, 15, 22),
        updatedAt: DateTime(2026, 8, 15, 22),
      );

  test('an answer is a moment, and it survives the round-trip', () {
    final plan = doctor(gather: [
      GatherItem(id: 'a', text: 'תעודת זהות', takenAt: DateTime(2026, 8, 16, 9)),
      const GatherItem(id: 'b', text: 'הפניה'),
    ]);
    final back = CalendarEvent.fromJson(plan.toJson());
    expect(back.gather.length, 2);
    expect(back.gather[0].taken, isTrue);
    expect(back.gather[0].takenAt, DateTime(2026, 8, 16, 9));
    expect(back.gather[1].taken, isFalse,
        reason: '"not yet" is a state, carried honestly');
    expect(back.gather[1].text, 'הפניה');
  });

  test('readiness is counted, never a tally of what is missing', () {
    final none = doctor(gather: const [
      GatherItem(id: 'a', text: 'x'),
      GatherItem(id: 'b', text: 'y'),
    ]);
    expect(none.hasGather, isTrue);
    expect(none.gatherTaken, 0);
    expect(none.gatherReady, isFalse);

    final all = none.copyWith(gather: [
      none.gather[0].copyWith(takenAt: DateTime(2026, 8, 16, 9)),
      none.gather[1].copyWith(takenAt: DateTime(2026, 8, 16, 9)),
    ]);
    expect(all.gatherTaken, 2);
    expect(all.gatherReady, isTrue);

    // A plan carrying nothing is not "ready" — there was nothing to ask.
    expect(doctor().hasGather, isFalse);
    expect(doctor().gatherReady, isFalse);
  });

  test('an answer can always be taken back', () {
    final item = GatherItem(
        id: 'a', text: 'מים', takenAt: DateTime(2026, 8, 16, 9));
    final undone = item.copyWith(takenAt: null);
    expect(undone.taken, isFalse);
    expect(undone.text, 'מים', reason: 'the thing itself is untouched');
  });

  test('a plan from before gather lists existed still opens', () {
    final old = CalendarEvent.fromJson({
      'id': 'old',
      'title': 'פגישה',
      'date': '2026-08-01',
      'createdAt': '2026-08-01T09:00:00.000',
      'updatedAt': '2026-08-01T09:00:00.000',
    });
    expect(old.gather, isEmpty);
    expect(old.hasGather, isFalse);
    // And an empty list adds no weight to the file every user already has.
    expect(old.toJson().containsKey('gather'), isFalse);
  });

  test('copyWith keeps the list unless it is the thing being changed', () {
    final plan = doctor(gather: const [GatherItem(id: 'a', text: 'תיק')]);
    expect(plan.copyWith(answer: 'done').gather.length, 1);
  });
}
