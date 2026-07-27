import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/pack/bns_wire.dart';

void main() {
  test('BNS Wire roundtrips a realistic data tree', () {
    final data = {
      'routines': [
        {
          'id': 'r1',
          'title': 'Morning meds',
          'recurrenceType': 'daily',
          'steps': [
            {'title': 'Pill', 'note': 'with water'},
            {'title': 'Water', 'note': null},
          ],
        },
        {
          'id': 'r2',
          'title': 'Walk',
          'recurrenceType': 'daily',
        },
      ],
      'captures': [
        {
          'id': 'c1',
          'at': '2026-07-26T10:00:00.000',
          'text': 'Elevator stuck again',
          'tags': ['need-help', 'routine'],
          'memoryLevel': 'remember',
        },
        {
          'id': 'c2',
          'at': '2026-07-26T10:00:00.000', // repeated string → pool win
          'text': 'Elevator stuck again',
          'tags': ['diary', 'goal-progress'],
        },
      ],
      'settings': {
        'deviceId': 'dev-1',
        'sttEnabled': true,
        'widgetForwardDays': 2,
        'quietMode': false,
        'retentionDays': null,
      },
      'emptyList': <Object?>[],
      'pi': 3.14159,
    };

    final bytes = BnsWire.encode(data);
    expect(utf8.decode(bytes.sublist(0, 4)), 'BNSD');
    final back = BnsWire.decode(bytes);
    expect(back, data);
  });

  test('wire is smaller than raw JSON on diary-shaped data', () {
    final data = {
      'captures': List.generate(
        200,
        (i) => {
          'id': 'c$i',
          'at': '2026-07-26T12:00:00.000',
          'text': 'A diary line with similar shape $i',
          'tags': ['diary', 'goal-progress', 'quick-thought'],
          'memoryLevel': 'quick',
          'contextNote': null,
        },
      ),
      'routines': List.generate(
        50,
        (i) => {
          'id': 'r$i',
          'title': 'Routine $i',
          'recurrenceType': 'daily',
          'isActive': true,
          'daysOfWeek': <int>[],
        },
      ),
    };
    final m = BnsWire.measure(data);
    // String pool + typed tags must beat verbose JSON keys.
    expect(m.wireBytes, lessThan(m.jsonBytes),
        reason: 'json=${m.jsonBytes} wire=${m.wireBytes}');
    // ignore: avoid_print
    print('WIRE vs JSON: json=${m.jsonBytes} wire=${m.wireBytes} '
        '(${(100 * m.wireBytes / m.jsonBytes).toStringAsFixed(1)}%)');
  });

  test('truncated / bad magic refuse cleanly', () {
    expect(() => BnsWire.decode([1, 2, 3]), throwsFormatException);
    final good = BnsWire.encode({'a': 1});
    expect(() => BnsWire.decode(good.sublist(0, 8)), throwsFormatException);
  });
}
