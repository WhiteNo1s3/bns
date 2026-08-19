/// The pairing ask stays a door the person can simply close.
///
/// Adapted from PR1 (prototyper-doors): its test wanted a labeled
/// «סגירה»; our dialog's worded decline is «לסרב», matching its own body
/// copy ("פשוט לסרב") — infinitive like every BNS door since the
/// gendered-imperative sweep (2026-08-19). What must hold: declining
/// needs no code, costs nothing, and shares nothing.
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

    await tester.tap(find.text('לסרב'));
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
    await tester.tap(find.text('צימוד מאובטח'));
    await tester.pumpAndSettle();

    expect(result, '993685');
  });
}
