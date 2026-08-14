import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/recording_text.dart';

void main() {
  test('Hebrew labels are הקלטה N', () {
    expect(recordingLabel(1, hebrew: true), 'הקלטה 1');
    expect(recordingLabel(2, hebrew: true), 'הקלטה 2');
    expect(recordingLabel(1, hebrew: false), 'Recording 1');
  });

  test('first take starts the box and ends with a newline', () {
    final out = appendRecordingBlock(
      current: '',
      label: 'הקלטה 1',
      transcript: 'הלכתי לחנות',
    );
    expect(out, 'הקלטה 1\nהלכתי לחנות\n');
  });

  test('second take starts on a new paragraph', () {
    final first = appendRecordingBlock(
      current: '',
      label: 'הקלטה 1',
      transcript: 'שלום',
    );
    final second = appendRecordingBlock(
      current: first,
      label: 'הקלטה 2',
      transcript: 'עוד מילה',
    );
    expect(second, 'הקלטה 1\nשלום\n\nהקלטה 2\nעוד מילה\n');
  });

  test('typed words stay; the next take continues after them', () {
    final out = appendRecordingBlock(
      current: 'הקלטה 1\nשלום\nועוד שורה שכתבתי',
      label: 'הקלטה 2',
      transcript: 'המשך',
    );
    expect(out.contains('ועוד שורה שכתבתי'), isTrue);
    expect(out.endsWith('הקלטה 2\nהמשך\n'), isTrue);
  });

  test('a quiet take still opens a labeled line to type into', () {
    expect(
      appendRecordingBlock(current: '', label: 'הקלטה 1', transcript: ''),
      'הקלטה 1\n\n',
    );
  });
}
