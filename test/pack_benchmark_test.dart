// Container benchmark (action item from the container evolution plan):
// measures pack/unpack on a realistic "heavy user" dataset so container
// decisions are made on numbers, not vibes. Runs as a normal test and
// asserts sane ceilings so a performance regression fails CI loudly.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/pack/bns_packers.dart';

void main() {
  test('benchmark: pack/unpack a heavy dataset stays responsive', () {
    final rnd = Random(42);

    // Realistic heavy day-to-day dataset: 500 captures with text,
    // 200 routines/logs, and 30 voice notes of ~200KB (already-compressed
    // audio simulated with random bytes — worst case for any compressor).
    final data = {
      'routines': List.generate(
          200,
          (i) => {
                'id': 'r$i',
                'title': 'Routine number $i with a reasonably long title',
                'recurrenceType': 'daily',
                'createdAt': '2026-07-05T10:00:00.000',
                'updatedAt': '2026-07-05T10:00:00.000',
              }),
      'captures': List.generate(
          500,
          (i) => {
                'id': 'c$i',
                'at': '2026-07-05T10:00:00.000',
                'text':
                    'Captured thought $i — a couple of sentences of real diary '
                        'text to make the payload honest about typical sizes.',
                'tags': ['diary', 'good'],
              }),
      'settings': {'deviceId': 'bench-device'},
    };
    final audio = List.generate(30, (i) {
      final bytes = List<int>.generate(200 * 1024, (_) => rnd.nextInt(256));
      return (name: 'cap_bench_$i.m4a', bytes: bytes);
    });

    // Race EVERY registered format on the identical dataset — the registry
    // is the entry list, this benchmark is the referee. Writer switches are
    // owner decisions made on these numbers, not vibes.
    for (final packer in BnsPackers.all) {
      // Warm-up round so JIT doesn't skew whichever format runs first.
      packer.unpack(packer.pack(
          manifest: const {'formatVersion': 2, 'warmup': true},
          data: const {'captures': <Object>[]},
          audioFiles: audio.sublist(0, 2)));

      final packWatch = Stopwatch()..start();
      final bytes = packer.pack(
        manifest: {'formatVersion': 2, 'bench': true},
        data: data,
        audioFiles: audio,
      );
      packWatch.stop();

      final unpackWatch = Stopwatch()..start();
      final back = packer.unpack(bytes);
      unpackWatch.stop();

      final sizeMb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      // ignore: avoid_print
      print(
          'BENCH ${packer.formatId}: pack=${packWatch.elapsedMilliseconds}ms '
          'unpack(with integrity)=${unpackWatch.elapsedMilliseconds}ms '
          'size=${sizeMb}MB (30x200KB audio + 700 records)');

      expect(back.audioFiles.length, 30);
      expect((back.data['captures'] as List).length, 500);

      // Regression ceilings (generous: CI machines vary). STORE/copy-based
      // packers land far below these; deflating audio again would blow way
      // past them — which is the point of the ceiling.
      expect(packWatch.elapsedMilliseconds, lessThan(4000),
          reason: '${packer.formatId} packing must stay responsive');
      expect(unpackWatch.elapsedMilliseconds, lessThan(4000),
          reason: '${packer.formatId} unpack + integrity must stay responsive');
    }
  });
}
