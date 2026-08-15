import 'package:bns/core/day_ideas.dart';
import 'package:bns/core/models/quick_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tomorrow = DateTime(2026, 8, 16);
  final tonight = DateTime(2026, 8, 15, 22, 10);

  QuickCapture idea({String? forDate, DateTime? at}) => QuickCapture(
        id: 'x',
        at: at ?? tonight,
        text: 'מטען, תיק, תעודה. חיפה מלחיצה.',
        forDate: forDate,
      );

  test('tonight bag waits on tomorrow', () {
    final c = idea(forDate: '2026-08-16');
    expect(captureBelongsToDate(c, tomorrow), isTrue);
    expect(captureBelongsToDate(c, DateTime(2026, 8, 15)), isFalse);
  });

  test('unpinned note stays on the day it was written', () {
    final c = idea(forDate: null, at: tonight);
    expect(captureBelongsToDate(c, DateTime(2026, 8, 15)), isTrue);
    expect(captureBelongsToDate(c, tomorrow), isFalse);
  });
}
