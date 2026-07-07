// Model round-trip tests: the .bns format depends on these staying stable.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/data/pack/bns_packers.dart';

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  return -1;
}

void main() {
  test('Routine JSON roundtrip', () {
    final now = DateTime.now();
    final r = Routine(
      id: 'r1',
      title: 'Morning stretch',
      recurrenceType: RecurrenceType.custom,
      daysOfWeek: const [1, 3, 5],
      time: '08:00',
      tags: const ['gentle'],
      createdAt: now,
      updatedAt: now,
    );
    final back = Routine.fromJson(r.toJson());
    expect(back.id, r.id);
    expect(back.recurrenceType, RecurrenceType.custom);
    expect(back.daysOfWeek, const [1, 3, 5]);
    expect(back.appliesOn(DateTime(2026, 7, 6)), true); // a Monday
  });

  test('AppSettings JSON roundtrip keeps keybinds and mad mode', () {
    final until = DateTime(2026, 7, 6, 12);
    final s = AppSettings(
      deviceId: 'dev-1',
      keybinds: const {'open_today': 'ctrl+t'},
      enabledKeybinds: const {'open_today': true},
      madModeUntil: until,
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.deviceId, 'dev-1');
    expect(back.keybinds['open_today'], 'ctrl+t');
    expect(back.enabledKeybinds['open_today'], true);
    expect(back.madModeUntil, until);
  });

  test('copyWith can clear nullable fields (mad mode burnout)', () {
    final s = AppSettings(madModeUntil: DateTime.now());
    final cleared = s.copyWith(madModeUntil: null);
    expect(cleared.madModeUntil, isNull);
  });

  test('QuickCapture trash roundtrip', () {
    final c = QuickCapture(
      id: 'c1',
      at: DateTime(2026, 7, 5),
      text: 'small win',
      tags: const ['diary'],
      deletedAt: DateTime(2026, 7, 6),
    );
    final back = QuickCapture.fromJson(c.toJson());
    expect(back.deletedAt, DateTime(2026, 7, 6));
    final restored = back.copyWith(deletedAt: null);
    expect(restored.deletedAt, isNull);
  });

  test('TrustedDevice keeps LAN kill switch through JSON', () {
    final d = TrustedDevice(
      id: 'peer-1',
      name: 'Phone',
      lastAddress: '192.168.1.20',
      lastSyncedAt: DateTime(2026, 7, 5),
      sharedSecret: 'c2VjcmV0',
      lanSyncAllowed: false,
    );
    final back = TrustedDevice.fromJson(d.toJson());
    expect(back.lanSyncAllowed, false);
    // Old .bns files without the field default to allowed.
    final legacy = TrustedDevice.fromJson({
      'id': 'x',
      'name': 'Old',
      'lastAddress': '',
      'lastSyncedAt': '2026-07-05T00:00:00.000',
    });
    expect(legacy.lanSyncAllowed, true);
  });

  test('Only real .bns payloads pass structural validation', () {
    // A hostile or garbage payload (e.g. renamed PDF) is rejected outright.
    expect(() => BnsImporter.validateBnsBytes('%PDF-1.7 not a bns'.codeUnits),
        throwsFormatException);
    expect(() => BnsImporter.validateBnsBytes(const [0x50, 0x4B]),
        throwsFormatException); // too short
    // Proper ZIP magic + plausible size passes the fast check.
    final zipLike = [0x50, 0x4B, 0x03, 0x04, ...List.filled(60, 0)];
    expect(() => BnsImporter.validateBnsBytes(zipLike), returnsNormally);
  });

  test('packer: marker, STORED entries, and full roundtrip', () {
    final fakeAudio = List<int>.generate(500, (i) => i % 251);
    final packer = BnsPackers.current;
    final bytes = packer.pack(
      manifest: {'formatVersion': 2, 'schema': 'bns/v2'},
      data: {
        'routines': [],
        'settings': {'deviceId': 'dev-1'}
      },
      audioFiles: [(name: 'cap_test.m4a', bytes: fakeAudio)],
    );

    expect(BnsImporter.hasBnsMark(bytes), true,
        reason: 'genuine v2 .bns must be recognizable without unpacking');
    expect(() => BnsImporter.validateBnsBytes(bytes), returnsNormally);
    expect(BnsPackers.detect(bytes), same(packer));

    // Full roundtrip through the packer itself (verifies integrity too).
    final back = packer.unpack(bytes);
    expect(back.manifest['packer'], 'zip-v2');
    expect(back.manifest['integrity']['algorithm'], 'sha256');
    expect(back.data['settings']['deviceId'], 'dev-1');
    expect(back.audioFiles.single.name, 'cap_test.m4a');
    expect(back.audioFiles.single.bytes, fakeAudio);

    // Foreign data is nobody's format.
    expect(BnsPackers.detect('%PDF-1.7 hostile'.codeUnits), isNull);
  });

  test('packer: tampered payload is rejected (unbreakable seal)', () {
    final packer = BnsPackers.current;
    final bytes = List<int>.from(packer.pack(
      manifest: {'formatVersion': 2},
      data: {
        'routines': [
          {'id': 'r1', 'title': 'real'}
        ]
      },
      audioFiles: const [],
    ));

    // Flip one byte inside the stored (uncompressed) data payload.
    final gzStart = _indexOf(bytes, utf8.encode('data.json.gz'));
    expect(gzStart, greaterThan(0));
    final target = gzStart + 40; // safely inside the stored payload bytes
    bytes[target] = bytes[target] ^ 0xFF;

    expect(() => packer.unpack(bytes), throwsFormatException,
        reason: 'a single flipped byte must never reach the database');
  });

  test('Keybind combos parse and pretty-print', () {
    expect(Keybinds.parse('ctrl+enter'), isNotNull);
    expect(Keybinds.parse('ctrl+,'), isNotNull);
    expect(Keybinds.parse('ctrl+shift+c'), isNotNull);
    expect(Keybinds.parse(''), isNull);
    expect(Keybinds.pretty('ctrl+shift+enter'), 'Ctrl+Shift+Enter');
  });
}
