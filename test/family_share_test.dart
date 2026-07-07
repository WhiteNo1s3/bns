// Family share (owner decision 2026-07-06): only events the user marked
// "family can know" ever leave — a filtered EXPORT, not a filtered view.
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/pack/bns_packers.dart';

void main() {
  test('shareWithFamily survives the JSON roundtrip and defaults to false',
      () {
    final e = CalendarEvent(
      id: 'e1',
      title: 'Neurologist',
      date: '2026-07-15',
      time: '14:30',
      shareWithFamily: true,
      createdAt: DateTime.utc(2026, 7, 6),
      updatedAt: DateTime.utc(2026, 7, 6),
    );
    final back = CalendarEvent.fromJson(e.toJson());
    expect(back.shareWithFamily, true);

    // Legacy events (no flag in JSON) stay private by default.
    final legacy = CalendarEvent.fromJson({
      'id': 'old',
      'title': 'Old event',
      'date': '2026-01-01',
    });
    expect(legacy.shareWithFamily, false,
        reason: 'private by default — sharing is always chosen');
  });

  test('family-share manifest and filtered data survive the container', () {
    final events = [
      CalendarEvent(
          id: 'e1',
          title: 'Wedding',
          date: '2026-08-02',
          isAllDay: true,
          shareWithFamily: true,
          createdAt: DateTime.utc(2026, 7, 6),
          updatedAt: DateTime.utc(2026, 7, 6)),
    ];
    // Same shape BnsExporter.exportFamilyShare builds.
    final bytes = BnsPackers.current.pack(
      manifest: {'formatVersion': 2, 'familyShare': true, 'schema': 'bns/v2'},
      data: {
        'routines': const <Object>[],
        'events': events.map((e) => e.toJson()).toList(),
        'captures': const <Object>[],
        'completionLogs': const <Object>[],
        'settings': {'shareName': 'Yossi'},
      },
      audioFiles: const [],
    );
    final back = BnsPackers.detect(bytes)!.unpack(bytes);
    expect(back.manifest['familyShare'], true);
    expect((back.data['events'] as List).length, 1);
    expect((back.data['routines'] as List), isEmpty,
        reason: 'nothing but chosen plans may exist in a family file');
    expect((back.data['captures'] as List), isEmpty);
    expect((back.data['settings'] as Map).keys, ['shareName'],
        reason: 'no preferences, no keybinds, no secrets in a family file');
  });
}
