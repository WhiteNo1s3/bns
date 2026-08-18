/// THE QUIET ROW — one line per thing (owner, 2026-08-19: "so crumbed
/// out with things inside it so I cannot tell what is next is what
/// isn't... all I wanted is to check what left in my day").
///
/// Held here: the row shows clock + name + state and NOTHING else; tap
/// is the quiet ✓ door; the pencil is the one miss door and leaves once
/// answered; an answered row keeps its place (dim, in place — THE DAY
/// STAYS STEADY); the bag shows only when there is a bag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/day_quiet_row.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget row) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Column(children: [row]))));
    await tester.pumpAndSettle();
  }

  testWidgets('open row: clock, name, pencil — tap answers', (tester) async {
    L.lang = 'he';
    var tapped = 0, skipped = 0;
    await pump(
        tester,
        DayQuietRow(
          time: '20:00',
          title: 'תרופות ערב',
          done: false,
          skipped: false,
          onTap: () => tapped++,
          onSkip: () => skipped++,
        ));

    expect(find.text('20:00'), findsOneWidget);
    expect(find.text('תרופות ערב'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.text('תרופות ערב'));
    expect(tapped, 1, reason: 'tap is the quiet ✓ door');
    await tester.tap(find.byIcon(Icons.edit_note));
    expect(skipped, 1, reason: 'the pencil is the one miss door');
  });

  testWidgets('done row: dim ✓ in place, no doors left', (tester) async {
    L.lang = 'he';
    await pump(
        tester,
        DayQuietRow(
          time: '08:00',
          title: 'תרופות בוקר',
          done: true,
          skipped: false,
          onTap: () {},
        ));

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsNothing);
    expect(find.text('תרופות בוקר'), findsOneWidget,
        reason: 'THE DAY STAYS STEADY — answered rows hold their place');
  });

  testWidgets('skipped row says it, quietly', (tester) async {
    L.lang = 'he';
    await pump(
        tester,
        DayQuietRow(
          time: '16:00',
          title: 'הליכה',
          done: false,
          skipped: true,
          onTap: () {},
        ));
    expect(find.text('לא קרה'), findsOneWidget);
    expect(find.byIcon(Icons.edit_note), findsNothing);
  });

  testWidgets('a bag shows only when there is a bag; steps ride quietly',
      (tester) async {
    L.lang = 'he';
    var bag = 0;
    await pump(
        tester,
        DayQuietRow(
          time: '10:00',
          title: 'רופא במרפאה',
          done: false,
          skipped: false,
          stepNote: 'חלק 2 מתוך 3',
          onTap: () {},
          onGather: () => bag++,
        ));
    expect(find.text('חלק 2 מתוך 3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.backpack_outlined));
    expect(bag, 1);
  });
}
