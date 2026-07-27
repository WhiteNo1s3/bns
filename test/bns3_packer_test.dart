import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/pack/bns_packers.dart';

void main() {
  final packer = Bns3Packer();
  final data = {
    'routines': [
      {'id': 'r1', 'title': 'Walk 🌿', 'recurrenceType': 'daily'}
    ],
    'captures': [
      {
        'id': 'c1',
        'at': '2026-07-27T10:00:00.000Z',
        'text': 'kept going',
        'tags': ['diary', 'goal-progress'],
      }
    ],
    'settings': {'deviceId': 'bns3-test', 'shareName': 'Yossi', 'sttEnabled': true},
  };
  final audio = [
    (name: 'cap_a.m4a', bytes: List<int>.generate(600, (i) => (i * 31) & 0xFF)),
    (name: 'cap_b.m4a', bytes: List<int>.generate(300, (i) => (i * 7) & 0xFF)),
  ];

  List<int> build() => packer.pack(
      manifest: {'formatVersion': 3, 'schema': 'bns/v2'},
      data: data,
      audioFiles: audio);

  test('bns3 roundtrip is lossless and sealed', () {
    final bytes = build();
    expect(utf8.decode(bytes.sublist(0, 4)), 'BNS3');

    final back = packer.unpack(bytes);
    expect(back.manifest['packer'], 'bns3-v1');
    expect((back.manifest['integrity'] as Map)['algorithm'], 'sha256');
    expect(back.data['settings'], data['settings']);
    expect((back.data['captures'] as List).first['text'], 'kept going');
    expect((back.data['routines'] as List).first['title'], 'Walk 🌿');
    expect(back.audioFiles.length, 2);
    expect(back.audioFiles.first.bytes, audio.first.bytes);
  });

  test('registry detects bns3; zip-v2 is the only save writer', () {
    final bytes = build();
    expect(BnsPackers.detect(bytes)?.formatId, 'bns3-v1');
    // Winner takes all: research formats read; saves always zip-v2.
    expect(BnsPackers.current.formatId, 'zip-v2');
  });

  test('one flipped byte in the data payload is rejected', () {
    final bytes = List<int>.from(build());
    // magic(4) + manifestLen(4) + manifest + codec(1) + dataLen(4) + data
    final manifestLen = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
    final dataStart = 4 + 4 + manifestLen + 1 + 4;
    bytes[dataStart + 8] ^= 0xFF;
    expect(() => packer.unpack(bytes), throwsFormatException);
  });

  test('flipped audio byte is rejected', () {
    final bytes = List<int>.from(build());
    bytes[bytes.length - 5] ^= 0xFF;
    expect(() => packer.unpack(bytes), throwsFormatException);
  });

  test('truncated file is refused', () {
    final bytes = build();
    expect(() => packer.unpack(bytes.sublist(0, bytes.length ~/ 2)),
        throwsFormatException);
  });

  test('foreign magic refused', () {
    expect(packer.canHandle(utf8.encode('BNS2....padding....')), isFalse);
    expect(() => packer.unpack(List.filled(64, 9)), throwsFormatException);
  });

  test('data-only bns3 never loses to zip on diary mass (codec race)', () {
    final diary = {
      'captures': List.generate(
        400,
        (i) => {
          'id': 'c$i',
          'at': '2026-07-27T09:00:00.000',
          'text': 'Thought number $i — similar shape, real diary weight.',
          'tags': ['diary', 'goal-progress', 'quick-thought'],
          'memoryLevel': 'quick',
        },
      ),
      'routines': List.generate(
        80,
        (i) => {
          'id': 'r$i',
          'title': 'Routine number $i with a reasonably long title',
          'recurrenceType': 'daily',
          'isActive': true,
        },
      ),
    };
    final bns3 = packer.pack(
        manifest: {'formatVersion': 3}, data: diary, audioFiles: const []);
    final zip = BnsZipPacker().pack(
        manifest: {'formatVersion': 2}, data: diary, audioFiles: const []);
    // ignore: avoid_print
    print('DATA-ONLY size: bns3=${bns3.length} zip-v2=${zip.length} '
        '(${(100 * bns3.length / zip.length).toStringAsFixed(1)}%)');
    // Codec race keeps us at or under classic gzip-json payload cost;
    // container overhead of BNS3 is less than ZIP central directory.
    expect(bns3.length, lessThanOrEqualTo(zip.length));
  });
}
