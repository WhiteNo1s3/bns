/// EVERY RECORDING IS KEPT (owner QA, 2026-08-14 — voice notes are "the
/// most important for the people").
///
/// One visit to the capture screen can hold several takes: the person
/// speaks, stops, speaks again. The words of all of them land in one
/// note. The voices must land there too — an earlier take used to be
/// left orphaned on disk, referenced by nothing, invisible forever.
///
/// These tests hold the line on the data itself: every take survives the
/// JSON round-trip the whole app is built on (the snapshot store, the
/// .bns file and LAN sync all serialize through it), and old files
/// without the field still open.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/quick_capture.dart';

void main() {
  QuickCapture threeTakes() => QuickCapture(
        id: 'm1',
        at: DateTime(2026, 8, 14, 15, 30),
        text: 'הקלטה 1\nלקנות חלב\n\nהקלטה 2\nולהתקשר לרופא',
        audioPath: '/audio/cap_aaa.m4a',
        extraAudioPaths: const ['/audio/cap_bbb.m4a', '/audio/cap_ccc.m4a'],
        transcript: 'לקנות חלב\nולהתקשר לרופא',
      );

  test('every take survives the JSON round-trip, in order', () {
    final back = QuickCapture.fromJson(threeTakes().toJson());
    expect(back.audioPath, '/audio/cap_aaa.m4a');
    expect(back.extraAudioPaths,
        ['/audio/cap_bbb.m4a', '/audio/cap_ccc.m4a']);
    expect(back.allAudioPaths, [
      '/audio/cap_aaa.m4a',
      '/audio/cap_bbb.m4a',
      '/audio/cap_ccc.m4a',
    ], reason: 'the memory view plays them in the order they were spoken');
  });

  test('the ordinary one-recording memory is unchanged', () {
    final one = QuickCapture(
      id: 'm2',
      at: DateTime(2026, 8, 14, 16),
      audioPath: '/audio/only.m4a',
    );
    final back = QuickCapture.fromJson(one.toJson());
    expect(back.extraAudioPaths, isEmpty);
    expect(back.allAudioPaths, ['/audio/only.m4a']);
    // A note with no voice at all has nothing to play.
    expect(QuickCapture(id: 'm3', at: DateTime(2026, 8, 14)).allAudioPaths,
        isEmpty);
  });

  test('a .bns written before takes existed still opens', () {
    // No 'extraAudioPaths' key at all — every file every user already has.
    final old = QuickCapture.fromJson({
      'id': 'old',
      'at': '2026-08-01T09:00:00.000',
      'text': 'from an older BNS',
      'audioPath': '/audio/old.m4a',
    });
    expect(old.extraAudioPaths, isEmpty);
    expect(old.allAudioPaths, ['/audio/old.m4a']);
  });

  test('copyWith keeps the other takes unless told otherwise', () {
    // The importer rewrites paths with copyWith — it must not drop voices.
    final moved = threeTakes().copyWith(audioPath: '/new/cap_aaa.m4a');
    expect(moved.extraAudioPaths.length, 2);
    expect(moved.allAudioPaths.first, '/new/cap_aaa.m4a');
  });
}
