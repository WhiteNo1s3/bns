/// THE EAR DOES NOT EDIT THE PERSON.
///
/// Owner, 2026-08-19: "curses must be inside the speech, no censor, no
/// changing curses into nonsense." A person venting says what they say,
/// and a rage sentence with the rage taken out is a lie about their day.
/// These tests hold the path from the mouth to the box: the words land
/// whole, the borrowed engine is asked with masking OFF, and the takes
/// queue instead of colliding (a mic that refuses a press reads as a
/// frozen app — the other half of the same complaint).
library;

import 'dart:io';

import 'package:bns/core/recording_text.dart';
import 'package:bns/services/ear.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the words land whole', () {
    test('a curse reaches the box exactly as it was said', () {
      const said = 'לעזאזל עם הרופא הזה, זה fucking מעצבן';
      final box = appendSpokenWords(current: '', words: said);
      expect(box.contains(said), isTrue);
      expect(box.contains('*'), isFalse);
    });

    test('nothing is softened when words join what is already written', () {
      final box = appendSpokenWords(
        current: 'בבוקר היה בסדר',
        words: 'ואז הכול הלך לעזאזל, שיט',
      );
      expect(box.contains('לעזאזל'), isTrue);
      expect(box.contains('שיט'), isTrue);
    });
  });

  test('the borrowed Android ear is asked with masking OFF', () {
    // The offline ear cannot censor — it is whisper.cpp reading a file.
    // The fallback CAN, and Google's default is to star curses out, so
    // both doors must keep saying so out loud.
    final kotlin = File(
      'android/app/src/main/kotlin/com/whiteno1se/bns/MainActivity.kt',
    );
    expect(kotlin.existsSync(), isTrue);
    final src = kotlin.readAsStringSync();
    final asks = RegExp(r'EXTRA_MASK_OFFENSIVE_WORDS,\s*false').allMatches(src);
    // One for the file ear, one for the popup door.
    expect(asks.length, greaterThanOrEqualTo(2));
    expect(src.contains('EXTRA_MASK_OFFENSIVE_WORDS, true'), isFalse);
  });

  group('takes queue, they do not collide', () {
    test('a second reading waits for the first, and order is kept', () async {
      final order = <String>[];
      var overlapping = false;
      var running = 0;

      Future<String> read(String name, int ms) => Ear.inTurn(() async {
            running++;
            if (running > 1) overlapping = true;
            await Future<void>.delayed(Duration(milliseconds: ms));
            order.add(name);
            running--;
            return name;
          });

      // The slow one was spoken first; it must still land first.
      final first = read('first', 60);
      final second = read('second', 1);
      await Future.wait([first, second]);

      expect(overlapping, isFalse);
      expect(order, ['first', 'second']);
    });

    test('a take nobody could read does not jam the ones after it', () async {
      final bad = Ear.inTurn<String>(() async => throw StateError('deaf'));
      await expectLater(bad, throwsStateError);
      expect(await Ear.inTurn(() async => 'still hearing'), 'still hearing');
    });
  });
}
