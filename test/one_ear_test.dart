/// ONE EAR, ONE MICROPHONE.
///
/// Owner, 2026-08-19: "we need to make the recorder work in order to use my
/// vision of pressing one button and using sst and record the man, or we
/// find a way to sst less fragile than android simple one that cancel
/// itself when you press any point of the screen."
///
/// The answer is the recording, not a live session: words are read off a
/// kept take afterwards, so nothing a finger does can cancel them. These
/// tests hold the two pure rules the rest of that machinery leans on —
/// the language handed to whisper, and the fact that one microphone can
/// only be held by one room at a time.
library;

import 'package:bns/services/ear.dart';
import 'package:bns/services/voice_take.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the language the ear is asked in', () {
    test('a full locale becomes the bare language whisper wants', () {
      expect(Ear.bareLang('he-IL'), 'he');
      expect(Ear.bareLang('en-US'), 'en');
      expect(Ear.bareLang('he_IL'), 'he');
    });

    test('Hebrew answers to its old name too', () {
      // Hebrew wore `iw` before it wore `he`, and old settings still say so.
      // A stale setting must not turn a Hebrew person into a foreign ear.
      expect(Ear.bareLang('iw_IL'), 'he');
      expect(Ear.bareLang('iw'), 'he');
    });

    test('an empty setting still speaks Hebrew, never nothing', () {
      expect(Ear.bareLang(''), 'he');
    });
  });

  group('one microphone', () {
    test('nobody holds it before anyone presses', () {
      expect(VoiceTake.isRecording, isFalse);
      expect(VoiceTake.holder, isNull);
      expect(VoiceTake.elapsed, Duration.zero);
    });

    test('stopping when nothing runs gives nothing back, quietly', () async {
      expect(await VoiceTake.stop(), isNull);
    });

    test('discarding nothing is not an error', () async {
      await VoiceTake.discard(null);
      await VoiceTake.discard('');
    });
  });
}
