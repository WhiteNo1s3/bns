/// The pairing ask stays a door the person can simply close.
///
/// Adapted from PR1 (prototyper-doors): its test wanted a labeled
/// «סגירה»; our dialog's worded decline is «סרב», matching its own body
/// copy ("אם לא ציפית לזה, פשוט סרב") — kept, not renamed. What must
/// hold: declining needs no code, costs nothing, and shares nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/features/sync/pairing_dialogs.dart';

void main() {
  setUp(() => L.lang = 'he');

  testWidgets('the worded decline dismisses without a code', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showEnterCodeDialog(
                context: context,
                peerName: 'Ben Phon',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('רוצה להתחבר'), findsOneWidget,
        reason: 'the ask names who is asking');

    await tester.tap(find.text('סרב'));
    await tester.pumpAndSettle();

    expect(find.textContaining('רוצה להתחבר'), findsNothing);
    expect(result, isNull, reason: 'declining shares nothing');
  });

  testWidgets('a typed code comes back to the caller', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showEnterCodeDialog(
                context: context,
                peerName: 'Ben Phon',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '993685');
    await tester.tap(find.text('צמד באופן מאובטח'));
    await tester.pumpAndSettle();

    expect(result, '993685');
  });
}
