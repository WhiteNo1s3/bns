/// THE POSTPONE BAR (owner, 2026-08-16: "simple vertical bar... each tick
/// 15 minutes, max 3 hours... this is up to you"). The decided details:
/// taps not drags, 12 ticks, time spoken the way a person says it — and
/// while a "later" runs, the hero stops offering that task, because later
/// that keeps being suggested is not later, it is nagging.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/routine.dart';
import 'package:bns/core/postpone.dart';
import 'package:bns/ui/widgets/next_hero_card.dart';

void main() {
  test('the bar speaks time the way a person does', () {
    expect(postponeLabel(1, hebrew: true), 'רבע שעה');
    expect(postponeLabel(2, hebrew: true), 'חצי שעה');
    expect(postponeLabel(4, hebrew: true), 'שעה');
    expect(postponeLabel(6, hebrew: true), 'שעה וחצי');
    expect(postponeLabel(8, hebrew: true), 'שעתיים');
    expect(postponeLabel(12, hebrew: true), 'שלוש שעות');
    expect(postponeLabel(1, hebrew: false), '15 minutes');
    expect(postponeLabel(5, hebrew: false), 'an hour and 15 minutes');
    expect(postponeLabel(6, hebrew: false), 'an hour and a half');
    expect(postponeLabel(12, hebrew: false), 'three hours');
  });

  test('the ticks stay inside the owner\'s bounds', () {
    expect(kPostponeTickMinutes * kPostponeMaxTicks, 180,
        reason: 'max 3 hours, per the owner');
    // Out-of-range asks clamp instead of crashing.
    expect(postponeLabel(0, hebrew: true), 'רבע שעה');
    expect(postponeLabel(99, hebrew: false), 'three hours');
  });

  test('while a "later" runs, the hero stops offering that task', () {
    Routine r(String id, String time) => Routine(
          id: id,
          title: id,
          recurrenceType: RecurrenceType.daily,
          time: time,
          createdAt: DateTime(2026, 8, 1),
          updatedAt: DateTime(2026, 8, 1),
        );
    final open = openRoutinesInNextOrder(
      todays: [r('meds', '07:00'), r('walk', '16:00')],
      doneIds: const {},
      skippedIds: const {},
      snoozedIds: const {'meds'},
      now: DateTime(2026, 8, 16, 7, 30),
    );
    expect(open.map((x) => x.id).toList(), ['walk'],
        reason: 'the postponed one is not nagged; it returns when it said');
  });
}
