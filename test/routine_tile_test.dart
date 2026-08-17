import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/routine.dart';
import 'package:bns/ui/widgets/routine_tile.dart';

void main() {
  setUp(() => L.lang = 'he');

  Routine morningStack() => Routine(
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

  testWidgets('open stack shows הבא on the remaining part', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutineTile(
          routine: morningStack(),
          isDone: false,
          onToggle: () {},
          onSkip: () {},
          stepsDone: 0,
          onStepDone: () {},
        ),
      ),
    ));
    expect(find.textContaining('הבא: לשתות כוס מים'), findsOneWidget);
  });

  testWidgets('skipped stack does not keep a הבא badge on drink water',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RoutineTile(
          routine: morningStack(),
          isDone: false,
          skippedToday: true,
          onToggle: () {},
          onSkip: () {},
          stepsDone: 0,
          onStepDone: () {},
        ),
      ),
    ));
    expect(find.textContaining('הבא:'), findsNothing);
    expect(find.textContaining('לשתות כוס מים'), findsNothing);
    expect(find.textContaining('לא קרה היום'), findsOneWidget);
  });
}
