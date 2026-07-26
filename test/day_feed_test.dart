import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/day_feed.dart';
import 'package:bns/core/models/models.dart';

void main() {
  final day = DateTime(2026, 7, 26);
  final dayStr = '2026-07-26';
  final now = DateTime(2026, 7, 26, 10, 0);

  Routine routine(String id, String title) => Routine(
        id: id,
        title: title,
        recurrenceType: RecurrenceType.daily,
        createdAt: now,
        updatedAt: now,
      );

  test('buildDayFeed orders morning to night and classifies kinds', () {
    final r = routine('r1', 'Meds');
    final feed = buildDayFeed(
      date: day,
      routines: [r],
      logs: [
        CompletionLog(
          id: 'l1',
          routineId: 'r1',
          date: dayStr,
          status: CompletionStatus.done,
          at: DateTime(2026, 7, 26, 8, 0),
        ),
        CompletionLog(
          id: 'l2',
          routineId: 'r1',
          date: dayStr,
          status: CompletionStatus.skipped,
          reason: 'Elevator stuck',
          at: DateTime(2026, 7, 26, 18, 0),
        ),
      ],
      captures: [
        QuickCapture(
          id: 'c1',
          at: DateTime(2026, 7, 26, 12, 0),
          text: 'Good lunch',
          tags: const ['diary', 'goal-progress'],
        ),
        QuickCapture(
          id: 'c2',
          at: DateTime(2026, 7, 26, 9, 30),
          text: 'Head hurt',
          tags: const ['need-help', 'routine'],
          linkedRoutineId: 'r1',
        ),
      ],
      events: [
        CalendarEvent(
          id: 'e1',
          title: 'Doctor',
          date: dayStr,
          time: '15:00',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    expect(feed.items.length, 5);
    // Chronological: done 08:00, need-help 09:30, diary 12:00, event 15:00, skip 18:00
    expect(feed.items[0].kind, DayFeedKind.done);
    expect(feed.items[1].kind, DayFeedKind.needHelp);
    expect(feed.items[1].words, 'Head hurt');
    expect(feed.items[2].kind, DayFeedKind.diary);
    expect(feed.items[3].kind, DayFeedKind.event);
    expect(feed.items[3].headline, 'Doctor');
    expect(feed.items[4].kind, DayFeedKind.skipped);
    expect(feed.items[4].words, 'Elevator stuck');
  });

  test('mad-vents excluded by default, included when asked', () {
    final vent = QuickCapture(
      id: 'v1',
      at: DateTime(2026, 7, 26, 11, 0),
      text: 'I hate everything',
      tags: const ['mad-vent'],
    );
    final without = buildDayFeed(
      date: day,
      routines: const [],
      logs: const [],
      captures: [vent],
      events: const [],
    );
    expect(without.items, isEmpty);

    final withVents = buildDayFeed(
      date: day,
      routines: const [],
      logs: const [],
      captures: [vent],
      events: const [],
      includeMadVents: true,
    );
    expect(withVents.items.length, 1);
    expect(withVents.items.first.kind, DayFeedKind.madVent);
  });

  test('auto summary never quotes or counts mad-vents', () {
    final r = routine('r1', 'Walk');
    final summary = buildDayAutoSummary(
      date: day,
      applicableRoutines: [r],
      logs: [
        CompletionLog(
          id: 'l1',
          routineId: 'r1',
          date: dayStr,
          status: CompletionStatus.done,
          at: now,
        ),
      ],
      captures: [
        QuickCapture(
          id: 'v1',
          at: now,
          text: 'SECRET RAGE WORDS that must not appear',
          tags: const ['mad-vent'],
        ),
        QuickCapture(
          id: 'c1',
          at: now,
          text: 'Nice sky',
          tags: const ['diary'],
        ),
      ],
      events: const [],
      t: (en, he) => en,
      dayLabel: 'Jul 26, 2026',
    );

    expect(summary.contains('SECRET RAGE'), isFalse);
    expect(summary.contains('mad-vent'), isFalse);
    expect(summary.contains('1 thoughts'), isTrue);
    expect(summary.contains('Walk'), isTrue);
  });

  test('care glance is soft and ignores vents', () {
    final r = routine('r1', 'Elevator trip');
    final glance = buildCareGlance(
      now: DateTime(2026, 7, 26),
      captures: [
        QuickCapture(
          id: 'c1',
          at: DateTime(2026, 7, 25, 9, 0),
          text: 'Stuck again',
          tags: const ['need-help'],
          linkedRoutineId: 'r1',
        ),
        QuickCapture(
          id: 'c2',
          at: DateTime(2026, 7, 24, 8, 0),
          text: 'Morning fog',
          tags: const ['need-help'],
          linkedRoutineId: 'r1',
        ),
        QuickCapture(
          id: 'v1',
          at: DateTime(2026, 7, 25, 20, 0),
          text: 'rage',
          tags: const ['mad-vent'],
        ),
      ],
      logs: const [],
      routines: [r],
      t: (en, he) => en,
    );

    expect(glance.hardNoteCount, 2);
    expect(glance.lines, isNotEmpty);
    expect(glance.lines.any((l) => l.toLowerCase().contains('missed')), isFalse);
    expect(glance.aboutTitles, contains('Elevator trip'));
    expect(glance.lines.any((l) => l.contains('morning')), isTrue);
  });

  test('dayItemMatchesQuery finds reasons and headlines', () {
    final item = DayFeedItem(
      kind: DayFeedKind.skipped,
      at: now,
      headline: 'Meds',
      words: 'Elevator stuck',
    );
    expect(dayItemMatchesQuery(item, 'elevator'), isTrue);
    expect(dayItemMatchesQuery(item, 'meds'), isTrue);
    expect(dayItemMatchesQuery(item, 'pizza'), isFalse);
  });
}
