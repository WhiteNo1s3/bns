// Contract tests for the BNS2 binary container (bns2-v1) — same bar the
// zip packer had to clear: roundtrip fidelity, registry detection, and
// hard rejection of tampered or truncated files.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/pack/bns_packers.dart';

void main() {
  final packer = BnsBinaryPacker();
  final data = {
    'routines': [
      {'id': 'r1', 'title': 'Walk 🌿', 'recurrenceType': 'daily'}
    ],
    'captures': [
      {'id': 'c1', 'at': '2026-07-06T10:00:00.000Z', 'text': 'kept going'}
    ],
    'settings': {'deviceId': 'bns2-test', 'shareName': 'Yossi'},
  };
  final audio = [
    (name: 'cap_a.m4a', bytes: List<int>.generate(600, (i) => (i * 31) & 0xFF)),
    (name: 'cap_b.m4a', bytes: List<int>.generate(300, (i) => (i * 7) & 0xFF)),
  ];

  List<int> build() => packer.pack(
      manifest: {'formatVersion': 2, 'schema': 'bns/v2'},
      data: data,
      audioFiles: audio);

  test('bns2 roundtrip is lossless and sealed', () {
    final bytes = build();
    expect(utf8.decode(bytes.sublist(0, 4)), 'BNS2',
        reason: 'identity magic at offset 0');

    final back = packer.unpack(bytes);
    expect(back.manifest['packer'], 'bns2-v1');
    expect((back.manifest['integrity'] as Map)['algorithm'], 'sha256');
    expect(back.data, data);
    expect(back.audioFiles.length, 2);
    expect(back.audioFiles.first.bytes, audio.first.bytes);
  });

  test('registry detects bns2 and still prefers zip for writing', () {
    final bytes = build();
    expect(BnsPackers.detect(bytes)?.formatId, 'bns2-v1');
    expect(BnsPackers.current.formatId, 'zip-v2',
        reason: 'writer switch is an owner decision, not a side effect');
  });

  test('one flipped byte in the data payload is rejected', () {
    final bytes = List<int>.from(build());
    // Locate the gz section: 4 magic + 4 len + manifest, then 4 len + gz.
    final manifestLen = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16);
    final gzStart = 4 + 4 + manifestLen + 4;
    bytes[gzStart + 10] ^= 0xFF;
    expect(() => packer.unpack(bytes), throwsFormatException);
  });

  test('flipped audio byte is rejected by the audio seal', () {
    final bytes = List<int>.from(build());
    bytes[bytes.length - 5] ^= 0xFF; // inside the last audio blob
    expect(() => packer.unpack(bytes), throwsFormatException);
  });

  test('truncated file gets the friendly damaged message, never a crash', () {
    final bytes = build();
    final cut = bytes.sublist(0, bytes.length ~/ 2);
    expect(() => packer.unpack(cut), throwsFormatException);
  });

  test('foreign bytes with the wrong magic are refused', () {
    expect(packer.canHandle(utf8.encode('PK not really a zip either')), false);
    expect(() => packer.unpack(List.filled(64, 7)), throwsFormatException);
  });
}
