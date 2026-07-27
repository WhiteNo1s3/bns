import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/pack/bns_file_imager.dart';
import 'package:bns/data/pack/bns_packer.dart';
import 'package:bns/data/pack/bns_zip_packer.dart';

/// The streaming imager (large-file path) and the in-memory packer must be
/// two faces of the SAME zip-v2 format: each must read what the other wrote,
/// seals included. This is the "database file sustains large recordings"
/// guarantee.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bns_stream_test_');
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> manifest() => {
        'formatVersion': 2,
        'mediaType': BnsZipPacker.mediaType,
        'exportedAt': '2026-07-26T10:00:00.000Z',
        'deviceId': 'test-device',
        'deviceName': 'Test Device',
        'schema': 'bns/v2',
      };

  Map<String, dynamic> sampleData() => {
        'routines': <Object>[],
        'events': <Object>[],
        'captures': [
          {
            'id': 'c1',
            'at': '2026-07-26T10:00:00.000Z',
            'text': 'buy bread',
            'transcript': 'buy bread',
            'audioPath': 'audio/cap_big.m4a',
          },
        ],
        'completionLogs': <Object>[],
        'settings': {'deviceId': 'test-device', 'deviceName': 'Test Device'},
      };

  /// Deterministic pseudo-random bytes, several MB — stands in for a long
  /// voice recording (already-compressed-looking, STORE path).
  List<int> bigAudioBytes(int size, int seed) {
    final r = Random(seed);
    return List<int>.generate(size, (_) => r.nextInt(256));
  }

  test('reliable save: verify passes; second save keeps .prev good', () async {
    final audioFile = File('${tmp.path}/a.m4a')
      ..writeAsBytesSync(bigAudioBytes(64 * 1024, 7));
    final outPath = '${tmp.path}/latest.bns';

    await BnsFileImager.packToFile(
      manifest: manifest(),
      data: sampleData(),
      audioFiles: [(name: 'a.m4a', path: audioFile.path)],
      outPath: outPath,
    );
    await BnsFileImager.verifyZipV2File(outPath);
    expect(BnsFileImager.hasZipV2Mark(File(outPath).readAsBytesSync()), isTrue);

    final firstBytes = File(outPath).readAsBytesSync();

    // Second image with different text — previous good becomes .prev.
    final data2 = sampleData();
    (data2['captures'] as List).first['text'] = 'buy milk';
    await BnsFileImager.packToFile(
      manifest: manifest(),
      data: data2,
      audioFiles: [(name: 'a.m4a', path: audioFile.path)],
      outPath: outPath,
    );
    await BnsFileImager.verifyZipV2File(outPath);
    expect(File('$outPath.prev').existsSync(), isTrue);
    expect(File('$outPath.prev').readAsBytesSync(), firstBytes);
    // Current file is the new content.
    final back = BnsZipPacker().unpack(File(outPath).readAsBytesSync());
    expect((back.data['captures'] as List).first['text'], 'buy milk');
  });

  test('streamed pack → in-memory unpack (seals verify, bytes identical)',
      () async {
    final audioBytes = bigAudioBytes(3 * 1024 * 1024, 42);
    final audioFile = File('${tmp.path}/cap_big.m4a')
      ..writeAsBytesSync(audioBytes);
    final outPath = '${tmp.path}/streamed.bns';

    await BnsFileImager.packToFile(
      manifest: manifest(),
      data: sampleData(),
      audioFiles: [(name: 'cap_big.m4a', path: audioFile.path)],
      outPath: outPath,
    );

    final bytes = File(outPath).readAsBytesSync();
    final packer = BnsZipPacker();
    expect(packer.canHandle(bytes), isTrue);

    // The identity marker must sit at its fixed offset (hasBnsMark contract).
    const marker = 'mimetype${BnsZipPacker.mediaType}';
    expect(String.fromCharCodes(bytes.sublist(30, 30 + marker.length)), marker);

    // unpack() verifies CRCs + SHA-256 seals — a throw fails the test.
    final unpacked = packer.unpack(bytes);
    expect(unpacked.manifest['packer'], 'zip-v2');
    expect((unpacked.data['captures'] as List).length, 1);
    expect((unpacked.data['captures'] as List).first['transcript'],
        'buy bread');
    expect(unpacked.audioFiles.length, 1);
    expect(unpacked.audioFiles.first.bytes, audioBytes);
  });

  test('in-memory pack → streamed unpack (audio lands on disk, verified)',
      () async {
    final audioBytes = bigAudioBytes(1024 * 1024, 7);
    final packed = BnsZipPacker().pack(
      manifest: manifest(),
      data: sampleData(),
      audioFiles: <BnsAudioEntry>[(name: 'cap_big.m4a', bytes: audioBytes)],
    );
    final bnsPath = '${tmp.path}/memory.bns';
    File(bnsPath).writeAsBytesSync(packed);

    final outDir = '${tmp.path}/extracted';
    final unpacked = await BnsFileImager.unpackToDir(
        bnsPath: bnsPath, audioOutDir: outDir);

    expect(unpacked.manifest['packer'], 'zip-v2');
    expect((unpacked.data['captures'] as List).first['text'], 'buy bread');
    expect(unpacked.audioFiles.length, 1);
    final extracted = File(unpacked.audioFiles.first.path);
    expect(extracted.existsSync(), isTrue);
    expect(extracted.readAsBytesSync(), audioBytes);
  });

  test('tampered audio is rejected and cleaned up', () async {
    final audioFile = File('${tmp.path}/cap_big.m4a')
      ..writeAsBytesSync(bigAudioBytes(256 * 1024, 3));
    final outPath = '${tmp.path}/tampered.bns';
    await BnsFileImager.packToFile(
      manifest: manifest(),
      data: sampleData(),
      audioFiles: [(name: 'cap_big.m4a', path: audioFile.path)],
      outPath: outPath,
    );

    // Flip one byte deep inside the stored audio region.
    final raf = File(outPath).openSync(mode: FileMode.append);
    final flipAt = File(outPath).lengthSync() - 4096;
    raf.setPositionSync(flipAt);
    final original = File(outPath).readAsBytesSync()[flipAt];
    raf.writeByteSync(original ^ 0xFF);
    raf.closeSync();

    final outDir = '${tmp.path}/tampered_out';
    await expectLater(
      BnsFileImager.unpackToDir(bnsPath: outPath, audioOutDir: outDir),
      throwsFormatException,
    );
    // Nothing partial survives.
    final leftovers = Directory(outDir).existsSync()
        ? Directory(outDir).listSync().length
        : 0;
    expect(leftovers, 0);
  });

  test('QuickCapture transcript survives JSON round-trip (and absence is fine)',
      () {
    final cap = QuickCapture(
      id: 'x',
      at: DateTime.utc(2026, 7, 26),
      text: 'call the doctor',
      transcript: 'call the doctor',
      audioPath: 'audio/cap_1.m4a',
    );
    final back = QuickCapture.fromJson(cap.toJson());
    expect(back.transcript, 'call the doctor');

    // Old files carry no transcript field — must load clean.
    final legacy = QuickCapture.fromJson({
      'id': 'y',
      'at': '2026-07-04T10:22:00.000Z',
      'text': 'old note',
    });
    expect(legacy.transcript, isNull);
  });
}
