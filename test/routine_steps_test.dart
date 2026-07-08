// The parts inside the action (owner, 2026-07-08): each part is its own
// entity with its own information, and legacy routines stay valid.
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/models.dart';

void main() {
  test('routine steps survive the JSON roundtrip in order', () {
    final r = Routine(
      id: 'r1',
      title: 'Morning meds',
      recurrenceType: RecurrenceType.daily,
      steps: const [
        RoutineStep(title: 'Take the pills', note: 'The blue box, top shelf'),
        RoutineStep(title: 'Drink a full glass of water'),
        RoutineStep(title: 'Check blood pressure', note: 'Write the number'),
      ],
      createdAt: DateTime.utc(2026, 7, 8),
      updatedAt: DateTime.utc(2026, 7, 8),
    );
    final back = Routine.fromJson(r.toJson());
    expect(back.steps.length, 3);
    expect(back.steps[0].title, 'Take the pills');
    expect(back.steps[0].note, 'The blue box, top shelf');
    expect(back.steps[1].note, null);
    expect(back.steps[2].title, 'Check blood pressure');
  });

  test('legacy routines without steps parse as single-part routines', () {
    final legacy = Routine.fromJson({
      'id': 'old',
      'title': 'Old routine',
      'recurrenceType': 'daily',
    });
    expect(legacy.steps, isEmpty);
  });

  test('todayOrder setting: timeline by default, roundtrips', () {
    expect(const AppSettings().todayOrder, 'timeline');
    final next = const AppSettings().copyWith(todayOrder: 'next');
    expect(AppSettings.fromJson(next.toJson()).todayOrder, 'next');
  });
}
