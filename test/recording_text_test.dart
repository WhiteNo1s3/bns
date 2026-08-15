/// THE BOX HOLDS ONLY THE PERSON'S WORDS (owner beta report, 2026-08-15:
/// a wordless take used to stamp "הקלטה 1" into the text — a header he
/// never said, standing where his words should be). The law now: words
/// append as plain paragraphs; a take with no words writes NOTHING.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/recording_text.dart';

void main() {
  test('labels exist for the playback chips, never for the text box', () {
    expect(recordingLabel(1, hebrew: true), 'הקלטה 1');
    expect(recordingLabel(2, hebrew: false), 'Recording 2');
  });

  test('heard words land as their own paragraph', () {
    expect(
      appendSpokenWords(current: '', words: 'לקנות חלב'),
      'לקנות חלב\n',
    );
    expect(
      appendSpokenWords(current: 'לקנות חלב\n', words: 'ולהתקשר לרופא'),
      'לקנות חלב\n\nולהתקשר לרופא\n',
    );
  });

  test('a wordless take writes NOTHING — no header, no stub', () {
    expect(appendSpokenWords(current: '', words: ''), '');
    expect(appendSpokenWords(current: '', words: '   '), '');
    expect(
      appendSpokenWords(current: 'מה שכבר כתבתי', words: '  '),
      'מה שכבר כתבתי',
      reason: 'the person\'s own text is never touched by an empty take',
    );
  });

  test('typed text keeps its place; new words never smash into it', () {
    final out = appendSpokenWords(
      current: 'שורה שהוקלדה ביד',
      words: 'ומילים שנאמרו',
    );
    expect(out, 'שורה שהוקלדה ביד\n\nומילים שנאמרו\n');
  });
}
