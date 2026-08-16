import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/didnt_happen.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/didnt_happen_sheet.dart';

void main() {
  setUp(() => L.lang = 'he');

  group('didntHappenOnDismiss — Close / tap-out / back', () {
    test('typed why logs the skip with those words', () {
      final r = didntHappenOnDismiss('too late');
      expect(r.skipped, isTrue);
      expect(r.reason, 'too late');
    });

    test('Hebrew why sticks', () {
      final r = didntHappenOnDismiss('  עייף  ');
      expect(r.skipped, isTrue);
      expect(r.reason, 'עייף');
    });

    test('empty close does not skip', () {
      expect(didntHappenOnDismiss('').skipped, isFalse);
      expect(didntHappenOnDismiss('   ').skipped, isFalse);
      expect(didntHappenOnDismiss('').reason, isNull);
    });

    test('English Skipped: prefix is not required and is not kept', () {
      final r = didntHappenOnDismiss('Skipped: עייף');
      expect(r.skipped, isTrue);
      expect(r.reason, 'עייף');
      expect(didntHappenOnDismiss('Skipped:').skipped, isFalse);
    });
  });

  group('didntHappenOnConfirm — the labeled door', () {
    test('always skips; empty reason is still a skip', () {
      final empty = didntHappenOnConfirm('');
      expect(empty.skipped, isTrue);
      expect(empty.reason, isNull);
    });

    test('confirm with words keeps the words', () {
      final r = didntHappenOnConfirm('too late');
      expect(r.skipped, isTrue);
      expect(r.reason, 'too late');
    });
  });

  group('miss sheet Close path', () {
    testWidgets('types a reason, hits סגירה — skip is logged with that reason',
        (tester) async {
      DidntHappenResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDidntHappenSheet(
                  context: context,
                  title: 'מים',
                  confirmLabel: L.t(
                      'It didn\'t happen today', 'זה לא קרה היום'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('זה לא קרה היום'), findsOneWidget);
      expect(find.text('סגירה'), findsOneWidget);
      expect(find.text('לשמור את זה — בקול או בכתיבה'), findsNothing,
          reason: 'one door — no second capture bar');

      await tester.enterText(find.byType(TextField), 'too late');
      await tester.tap(find.text('סגירה'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.skipped, isTrue,
          reason: 'Close with words MUST log the skip');
      expect(result!.reason, 'too late');
    });

    testWidgets('empty Close does not skip', (tester) async {
      DidntHappenResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDidntHappenSheet(
                  context: context,
                  title: 'מים',
                  confirmLabel: L.t(
                      'It didn\'t happen today', 'זה לא קרה היום'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('סגירה'));
      await tester.pumpAndSettle();
      expect(result!.skipped, isFalse);
      expect(result!.reason, isNull);
    });

    testWidgets('tap-out with typed why still skips', (tester) async {
      DidntHappenResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDidntHappenSheet(
                  context: context,
                  title: 'מים',
                  confirmLabel: L.t(
                      'It didn\'t happen today', 'זה לא קרה היום'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'עייף');
      // Barrier is above the sheet; tap the top of the screen.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(result!.skipped, isTrue);
      expect(result!.reason, 'עייף');
    });

    testWidgets('confirm door stays above a tall keyboard', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showDidntHappenSheet(
                  context: context,
                  title: 'מים',
                  confirmLabel: L.t(
                      'It didn\'t happen today', 'זה לא קרה היום'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final confirm = find.text('זה לא קרה היום');
      expect(confirm, findsOneWidget);
      final viewH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(viewH - 280 + 8),
          reason: 'confirm must sit above the keyboard, not under it');
    });
  });
}
