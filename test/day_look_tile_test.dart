import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/day_look_tile.dart';

void main() {
  setUp(() => L.lang = 'he');

  testWidgets('future look tile is name + time — no box, no pencil',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DayLookTile(title: 'כדורים', time: '08:00'),
      ),
    ));

    expect(find.text('כדורים'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    expect(find.byIcon(Icons.check_box), findsNothing);
    expect(find.byIcon(Icons.edit_note), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.text('לא קרה'), findsNothing);
    expect(find.text("Didn't happen"), findsNothing);
  });

  testWidgets('tap says the day has not come — a label, not an editor',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayLookTile(
          title: 'כדורים',
          time: '08:00',
          onTap: () => taps++,
        ),
      ),
    ));
    await tester.tap(find.text('כדורים'));
    await tester.pump();
    expect(taps, 1);
  });

  test('Hebrew-first label for a day that has not come', () {
    L.lang = 'he';
    expect(dayHasNotComeLabel(), 'היום הזה עוד לא הגיע — הוא יחכה לך.');
    L.lang = 'en';
    expect(dayHasNotComeLabel(),
        'The day has not come — it can wait for you.');
  });
}
