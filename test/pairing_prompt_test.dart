import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/pairing_prompt.dart';

void main() {
  group('pairAskDisposition', () {
    test('a trusted friend stays quiet — even mid-Done', () {
      expect(
        pairAskDisposition(alreadyTrusted: true, completing: false),
        PairAskDisposition.stayQuiet,
      );
      expect(
        pairAskDisposition(alreadyTrusted: true, completing: true),
        PairAskDisposition.stayQuiet,
        reason: 'trust is in the file; Done is not a reason to re-pair',
      );
    });

    test('a new device waits while Done / skip is in flight', () {
      expect(
        pairAskDisposition(alreadyTrusted: false, completing: true),
        PairAskDisposition.waitForDone,
      );
    });

    test('a truly new device, idle, may see the sheet', () {
      expect(
        pairAskDisposition(alreadyTrusted: false, completing: false),
        PairAskDisposition.prompt,
      );
    });

    test('a leftover extra copy does not stack a second sheet', () {
      expect(
        pairAskDisposition(
          alreadyTrusted: false,
          completing: false,
          promptAlreadyOpen: true,
        ),
        PairAskDisposition.stayQuiet,
      );
    });
  });

  group('PairingGate — Done finishes first', () {
    test('waitUntilIdle unblocks after complete ends', () async {
      final gate = PairingGate();
      var markedDone = false;
      final complete = gate.run(() async {
        await Future<void>.delayed(Duration.zero);
        markedDone = true;
      });
      expect(gate.isCompleting, isTrue);
      final pairWait = gate.waitUntilIdle();
      await complete;
      expect(markedDone, isTrue, reason: 'Done must finish even if a pair ask is pending');
      await pairWait;
      expect(gate.isCompleting, isFalse);
    });

    test('idle wait returns immediately', () async {
      final gate = PairingGate();
      await gate.waitUntilIdle();
      expect(gate.isCompleting, isFalse);
    });

    test('a second prompt while one is open stays quiet', () async {
      final gate = PairingGate();
      final first = gate.runPrompt(() async => 'code');
      final second = gate.runPrompt(() async => 'other');
      expect(await second, isNull);
      expect(await first, 'code');
    });
  });
}
