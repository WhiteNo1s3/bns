// Cross-implementation referee for the .bns container.
//
// zip-v2 now has two official writers/readers: the Dart packer
// (lib/data/pack/bns_zip_packer.dart, used by the app) and the JS core inside
// satellite/bns-web.html. This tool lets each side verify the other's files:
//
//   dart run tool/cross_check.dart make <out.bns> [zip|bns2|streamed]  # write a fixture
//   dart run tool/cross_check.dart verify <file.bns>          # unpack + verify any .bns
//
// 'streamed' writes through BnsFileImager (the large-file streaming writer
// the app uses for exports) — the fixture must verify identically to 'zip'.
//
// Pure Dart (archive + crypto only) — runs with `dart run`, no device needed.
import 'dart:convert';
import 'dart:io';

import 'package:bns/data/pack/bns_file_imager.dart';
import 'package:bns/data/pack/bns_packers.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: cross_check.dart make|verify <path>');
    exit(2);
  }
  final mode = args[0];
  final path = args[1];

  if (mode == 'make') {
    final data = {
      'routines': [
        {
          'id': 'r1',
          'title': 'Morning meds',
          'recurrenceType': 'daily',
          'daysOfWeek': <int>[],
          'isActive': true,
          'tags': ['health'],
          'firstStepOnlyDefault': false,
          'createdAt': '2026-07-05T10:00:00.000Z',
          'updatedAt': '2026-07-05T10:00:00.000Z',
        }
      ],
      'events': <Object>[],
      'captures': [
        {'id': 'c1', 'at': '2026-07-05T10:00:00.000Z', 'text': 'One'},
        {'id': 'c2', 'at': '2026-07-05T11:00:00.000Z', 'text': 'Two 💚'},
        {
          'id': 'c3',
          'at': '2026-07-05T12:00:00.000Z',
          'text': 'Three',
          'audioPath': 'audio/cap_fix_a.m4a',
        },
      ],
      'completionLogs': <Object>[],
      'settings': {'deviceId': 'dart-fixture', 'deviceName': 'Dart Fixture'},
    };
    final audio = [
      (name: 'cap_fix_a.m4a', bytes: List<int>.generate(2048, (i) => (i * 7) & 0xFF)),
      (name: 'cap_fix_b.m4a', bytes: List<int>.generate(1024, (i) => (i * 13) & 0xFF)),
    ];
    final format = args.length > 2 ? args[2] : 'zip';
    final manifest = {
      'formatVersion': 2,
      'mediaType': 'application/x-bns',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': 'dart-fixture',
      'deviceName': 'Dart Fixture',
      'schema': 'bns/v2',
    };

    if (format == 'streamed') {
      // The app's large-file writer: audio referenced by path, streamed in.
      final tmpDir = Directory.systemTemp.createTempSync('bns_xcheck_');
      final refs = <({String name, String path})>[];
      for (final a in audio) {
        final f = File('${tmpDir.path}/${a.name}')..writeAsBytesSync(a.bytes);
        refs.add((name: a.name, path: f.path));
      }
      await BnsFileImager.packToFile(
        manifest: manifest,
        data: data,
        audioFiles: refs,
        outPath: path,
      );
      tmpDir.deleteSync(recursive: true);
      stdout.writeln(
          'wrote $path (${File(path).lengthSync()} bytes, zip-v2 streamed)');
      return;
    }

    final packer = format == 'bns2' ? BnsBinaryPacker() : BnsPackers.current;
    final bytes = packer.pack(
      manifest: manifest,
      data: data,
      audioFiles: audio,
    );
    File(path).writeAsBytesSync(bytes);
    stdout.writeln('wrote $path (${bytes.length} bytes, ${packer.formatId})');
    return;
  }

  if (mode == 'verify') {
    final bytes = File(path).readAsBytesSync();
    final packer = BnsPackers.detect(bytes);
    if (packer == null) {
      stderr.writeln('FAIL: no packer claims this file');
      exit(1);
    }
    // unpack runs structure + CRC + SHA-256 integrity checks and throws on any failure.
    final unpacked = packer.unpack(bytes);
    final data = unpacked.data;
    stdout.writeln('VERIFIED by ${packer.formatId}:');
    stdout.writeln('  manifest.packer   = ${unpacked.manifest['packer']}');
    stdout.writeln('  integrity         = ${(unpacked.manifest['integrity'] as Map?)?['algorithm']}');
    stdout.writeln('  routines/events   = ${(data['routines'] as List?)?.length}/${(data['events'] as List?)?.length}');
    stdout.writeln('  captures/logs     = ${(data['captures'] as List?)?.length}/${(data['completionLogs'] as List?)?.length}');
    stdout.writeln('  audio entries     = ${unpacked.audioFiles.length}');
    stdout.writeln('  data sample       = ${jsonEncode((data['captures'] as List?)?.first ?? {})}');
    return;
  }

  stderr.writeln('unknown mode: $mode');
  exit(2);
}
