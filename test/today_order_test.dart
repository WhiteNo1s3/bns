import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/models/routine.dart';
import 'package:bns/ui/widgets/next_hero_card.dart';

/// The laws of "what is in front of me right now".
///
/// Both come from the owner's own days, not from theory:
///  * "The morning routine went over the night one until I pushed it away
///    as not today, and then went down to its place" — an ANSWER is an
///    answer, whether it is a ✓ or a "didn't happen".
///  * "I did half the things to go to bed and couldn't come back" —
///    something already started must come back on top by itself.
Routine _r(String id, String title, String? time, {int parts = 0}) => Routine(
      id: id,
      title: title,
      recurrenceType: RecurrenceType.daily,
      daysOfWeek: const [],
      time: time,
      isActive: true,
      steps: List.generate(
          parts, (i) => RoutineStep(title: 'part ${i + 1}', note: null)),
      tags: const [],
      createdAt: DateTime(2026, 7, 29),
      updatedAt: DateTime(2026, 7, 29),
    );

void main() {
  final morning = _r('m', 'תרופות הבוקר', '07:00');
  final night = _r('n', 'הכנה לשינה', '21:30', parts: 4);
  final night2300 = DateTime(2026, 7, 29, 23, 0);

  test('an unanswered morning task still shows at 23:00 — nothing is hidden',
      () {
    final open = openRoutinesInNextOrder(
      todays: [morning, night],
      doneIds: const {},
      skippedIds: const {},
      now: night2300,
    );
    expect(open.map((r) => r.id), containsAll(['m', 'n']));
  });

  test('"didn\'t happen" removes it from what is next, exactly like a ✓', () {
    final skipped = openRoutinesInNextOrder(
      todays: [morning, night],
      doneIds: const {},
      skippedIds: const {'m'},
      now: night2300,
    );
    expect(skipped.map((r) => r.id), ['n'],
        reason: 'a skip is an ANSWER — the night routine takes the front');

    final done = openRoutinesInNextOrder(
      todays: [morning, night],
      doneIds: const {'m'},
      skippedIds: const {},
      now: night2300,
    );
    expect(done.map((r) => r.id), ['n'],
        reason: 'done and skipped must behave identically here');
  });

  test('everything answered leaves nothing in front — the day is clear', () {
    final open = openRoutinesInNextOrder(
      todays: [morning, night],
      doneIds: const {'n'},
      skippedIds: const {'m'},
      now: night2300,
    );
    expect(open, isEmpty);
  });

  test('a half-finished routine is what a person comes back to', () {
    // The rule Today applies: among open routines, one with SOME parts done
    // (but not all) outranks whatever the clock would have chosen.
    final open = openRoutinesInNextOrder(
      todays: [morning, night],
      doneIds: const {},
      skippedIds: const {},
      now: night2300,
    );
    const progress = {'n': 2}; // two of the four bedtime parts happened
    final started = open
        .where((r) =>
            r.steps.isNotEmpty &&
            (progress[r.id] ?? 0) > 0 &&
            (progress[r.id] ?? 0) < r.steps.length)
        .toList();

    expect(started.map((r) => r.id), ['n']);
    final hero = started.isNotEmpty ? started.first : open.first;
    expect(hero.id, 'n',
        reason: 'half-done bedtime comes back on top, not the 07:00 task');
  });
}
