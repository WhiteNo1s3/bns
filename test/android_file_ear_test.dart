import 'package:bns/services/android_file_stt.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ear probe (a bundled "שלום, מה שלומך היום?") decides whether a
/// phone's recognizer really read our FILE — so the match must survive
/// engine punctuation and final-letter spelling, and must never pass on
/// silence or room noise (a variant that ignores the file extra listens
/// to the mic instead; whatever it hears must not count as a pass).
void main() {
  group('the ear probe knows its own sentence', () {
    test('the full sentence passes, punctuation and all', () {
      expect(AndroidFileStt.probeMatches('שלום, מה שלומך היום?'), isTrue);
    });

    test('final letters fold — שלום is found inside שלומך', () {
      expect(AndroidFileStt.probeMatches('מה שלומך היום'), isTrue);
    });

    test('an empty answer is not a working ear', () {
      expect(AndroidFileStt.probeMatches(''), isFalse);
    });

    test('room noise does not pass as the sentence', () {
      expect(AndroidFileStt.probeMatches('בסדר גמור תודה רבה'), isFalse);
    });

    test('one lonely hello is not enough to trust a door', () {
      expect(AndroidFileStt.probeMatches('שלום'), isFalse);
    });
  });
}
