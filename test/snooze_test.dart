/// "LATER, I SAID SO" (owner, 2026-08-15: "move a task by will for a few
/// hours") — a snooze is the person's word, and the plan must keep it:
/// a one-shot knock at the chosen time, by name, surviving the shade
/// sweeps because it lives in the plan itself, and never nagging about
/// things that no longer exist.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/reminder_plan.dart';

void main() {
  setUp(() => L.lang = 'he');

  final now = DateTime(2026, 8, 16, 9, 0);

  Routine pills() => Routine(
        id: 'r1',
        title: 'תרופות הבוקר',
        recurrenceType: RecurrenceType.daily,
        time: '07:00',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  test('a snoozed reminder returns at the chosen time, by name', () {
    final at = now.add(const Duration(hours: 2));
    final plan = planReminders(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
      snoozes: {'routine:r1': at},
    );
    final snooze = plan.where((p) => p.repeat == PlannedRepeat.none).toList();
    expect(snooze, hasLength(1));
    expect(snooze.single.firstAt, at);
    expect(snooze.single.body, contains('תרופות הבוקר'),
        reason: 'the knock says WHAT returns — a nameless reminder is noise');
    expect(snooze.single.payload, 'routine:r1',
        reason: 'the returned knock answers like any reminder (done/later/why)');
  });

  test('the regular daily reminder still exists alongside the snooze', () {
    final plan = planReminders(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
      snoozes: {'routine:r1': now.add(const Duration(hours: 2))},
    );
    expect(plan.where((p) => p.repeat == PlannedRepeat.daily), hasLength(1));
  });

  test('a snooze for something that no longer exists stays silent', () {
    final plan = planReminders(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
      snoozes: {'routine:deleted': now.add(const Duration(hours: 2))},
    );
    expect(plan.where((p) => p.repeat == PlannedRepeat.none), isEmpty);
  });

  test('an expired snooze adds nothing', () {
    final plan = planReminders(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
      snoozes: {'routine:r1': now.subtract(const Duration(minutes: 5))},
    );
    expect(plan.where((p) => p.repeat == PlannedRepeat.none), isEmpty);
  });

  test('a new snooze changes the fingerprint, so it really registers', () {
    final without = reminderFingerprint(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
    );
    final with2h = reminderFingerprint(
      routines: [pills()],
      events: const [],
      settings: const AppSettings(),
      now: now,
      snoozes: {'routine:r1': now.add(const Duration(hours: 2))},
    );
    expect(without == with2h, isFalse);
  });
}
