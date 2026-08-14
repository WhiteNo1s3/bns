/// THE VOID MUST STAY CLOSED (owner QA, 2026-08-14: "I give text and voices
/// to the void"). One failed disk write used to kill every write after it —
/// the app kept saying "saved" while nothing reached the disk until restart,
/// and everything since the failure evaporated with the process.
///
/// These tests point the store at a temp folder and prove the new pipeline:
///   - a failing write never throws at the caller and never blocks later
///     writes: when storage recovers, the NEWEST full snapshot lands, so
///     nothing said in between is lost;
///   - the app says so honestly while it lasts (saveTrouble), and calms
///     down by itself on the first landed write;
///   - a main file that vanishes or dies mid-swap is rescued from the
///     `.tmp` / `.bak` net on the next load instead of starting empty.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';

/// Extends the real platform class, so the platform-interface token check
/// accepts it — no mock machinery needed.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory home;

  QuickCapture cap(String id, String words) => QuickCapture(
        id: id,
        at: DateTime(2026, 8, 14, 12, 0),
        text: words,
        tags: const ['quick-thought'],
      );

  File storeFile() => File(p.join(home.path, 'bns_data.json'));

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_store_test_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    home = Directory(p.join(root.path, 'home'))..createSync(recursive: true);
    await IsarService.debugResetForTest();
    await BnsHome.setDir(home);
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('a failing write never voids what comes after it', () async {
    await IsarService.addCapture(cap('c1', 'first words'));
    await IsarService.flush();
    expect(await storeFile().readAsString(), contains('first words'));
    expect(IsarService.saveTrouble.value, isNull);

    // Sabotage: a DIRECTORY squats on the .tmp path — every write attempt
    // now fails exactly like a refusing disk.
    final squatter = Directory('${storeFile().path}.tmp')..createSync();

    await IsarService.addCapture(cap('c2', 'spoken into the storm'));
    await IsarService.flush(); // completes even while failing — never hangs
    expect(IsarService.saveTrouble.value, isNotNull,
        reason: 'failing saves must be said honestly, never silent');
    expect(await storeFile().readAsString(), isNot(contains('storm')),
        reason: 'sanity: the sabotaged write really did fail');

    // Storage recovers; the very next change must carry EVERYTHING out.
    squatter.deleteSync();
    await IsarService.addCapture(cap('c3', 'after the storm'));
    await IsarService.flush();

    final onDisk = await storeFile().readAsString();
    expect(onDisk, contains('first words'));
    expect(onDisk, contains('spoken into the storm'),
        reason: 'the failed-save words must ride the next snapshot — '
            'nothing said during the outage may vanish');
    expect(onDisk, contains('after the storm'));
    expect(IsarService.saveTrouble.value, isNull,
        reason: 'the banner calms down by itself once a write lands');
  });

  test('a vanished main file is rescued from the .bak net on load', () async {
    await IsarService.addCapture(cap('c1', 'the kept memory'));
    await IsarService.flush();
    // A second write sets the first snapshot aside as .bak.
    await IsarService.addCapture(cap('c2', 'the newer memory'));
    await IsarService.flush();
    expect(File('${storeFile().path}.bak').existsSync(), isTrue);

    // Disaster between the swap's two renames: the main file is gone.
    storeFile().deleteSync();
    await IsarService.debugResetForTest(); // pretend app restart

    final captures = await IsarService.getAllCaptures();
    expect(captures.map((c) => c.text), contains('the kept memory'),
        reason: 'load must fall back to .bak instead of starting empty');
  });

  test('a finished .tmp write that missed its rename is honored on load',
      () async {
    // A snapshot that reached the disk whole but never got renamed —
    // the crash happened between write and swap.
    final tmp = File('${storeFile().path}.tmp');
    final data = {
      'version': 1,
      'seeded': true,
      'cleanExit': true,
      'settings': const AppSettings().toJson(),
      'routines': const [],
      'events': const [],
      'captures': [cap('c1', 'almost lost words').toJson()],
      'logs': const [],
      'trusted': const [],
      'stepProgress': const {},
    };
    tmp.writeAsStringSync(jsonEncode(data), flush: true);

    final captures = await IsarService.getAllCaptures();
    expect(captures.map((c) => c.text), contains('almost lost words'));
  });
}
