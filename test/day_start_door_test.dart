import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/day_start_door.dart';

void main() {
  setUp(() => L.lang = 'he');

  testWidgets('unset 0 shows the question and 15:00 on Today', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 0,
          onPicked: (h) => picked = h,
        ),
      ),
    ));

    expect(find.text('מתי היום שלך מתחיל?'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(find.text('When does your day start?'), findsNothing);
    expect(picked, isNull, reason: 'first paint must not pick 15');

    await tester.ensureVisible(find.text('15:00'));
    await tester.tap(find.text('15:00'));
    await tester.pump();
    expect(picked, 15);
  });

  testWidgets('first paint of unset 0 does not fire onPicked', (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 0,
          onPicked: (h) => picked = h,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('מתי היום שלך מתחיל?'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    expect(picked, isNull);
  });

  testWidgets('a set 15 quiets the door — no maze', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 15,
          onPicked: _noop,
        ),
      ),
    ));

    expect(find.text('מתי היום שלך מתחיל?'), findsNothing);
    expect(find.text('15:00'), findsNothing);
    expect(find.text('When does your day start?'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('English line is the same door', (tester) async {
    L.lang = 'en';
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 0,
          onPicked: (h) => picked = h,
        ),
      ),
    ));

    expect(find.text('When does your day start?'), findsOneWidget);
    expect(find.text('מתי היום שלך מתחיל?'), findsNothing);
    await tester.ensureVisible(find.text('15:00'));
    await tester.tap(find.text('15:00'));
    await tester.pump();
    expect(picked, 15);
  });
}

void _noop(int _) {}
