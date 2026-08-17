import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/day_start_door.dart';

/// The day-start door on Today. The sixteen-chip wall became ONE worded
/// door opening the fusion sheet (owner, 2026-08-18: "less nightmare to
/// look at a long list") — the laws it held stay held: first paint never
/// picks an hour; only the sheet's confirm fires onPicked; a set hour
/// quiets the door to a small tappable line (changeable, never a maze).
void main() {
  setUp(() => L.lang = 'he');

  Future<void> pickViaSheet(WidgetTester tester, String hour) async {
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
        find.text(hour), find.byType(ListView), const Offset(0, -52));
    await tester.tap(find.text(hour));
    await tester.pump();
    await tester.tap(find.textContaining(L.isHebrew ? 'לקבוע' : 'Set'));
    await tester.pumpAndSettle();
  }

  testWidgets('unset 0 shows the question; the sheet picks 15',
      (tester) async {
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
    expect(find.text('When does your day start?'), findsNothing);
    expect(picked, isNull, reason: 'first paint must not pick an hour');

    await tester.tap(find.text('מתי היום שלך מתחיל?'));
    await pickViaSheet(tester, '15:00');
    expect(picked, 15);
  });

  testWidgets('first paint of unset 0 does not fire onPicked',
      (tester) async {
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
    expect(picked, isNull);
  });

  testWidgets('a set 15 quiets the door to a small changeable line',
      (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 15,
          onPicked: (h) => picked = h,
        ),
      ),
    ));

    // Quiet: no question shouted, no chip wall — one small line that
    // says the fact and opens the sheet when the person wants a change.
    expect(find.text('מתי היום שלך מתחיל?'), findsNothing);
    expect(find.textContaining('היום שלך מתחיל ב־15:00'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);

    await tester.tap(find.textContaining('היום שלך מתחיל ב־15:00'));
    await pickViaSheet(tester, '16:00');
    expect(picked, 16, reason: 'changing later never needs הגדרות');
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
    await tester.tap(find.text('When does your day start?'));
    await pickViaSheet(tester, '15:00');
    expect(picked, 15);
  });
}
