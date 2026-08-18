/// THE ISOLATION DOOR — a pinned instance can never touch the live home.
///
/// docs/testing-live.md promised `--data-dir` and the Dart never had it;
/// a Windows test seed overwrote the LIVE store through shared Documents
/// (caregiver report, 2026-08-16). These tests hold the door:
/// a pinned process reads its own home, and the shared pointer file is
/// neither read nor written while pinned.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/data/local/bns_home.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_home_isolation_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    BnsHome.debugClearForcedForTest();
  });

  tearDown(() async {
    BnsHome.debugClearForcedForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('--data-dir pins the home for this process', () async {
    final isolated = p.join(root.path, 'harness-l4');
    BnsHome.applyStartupArgs(['--data-dir=$isolated']);
    expect((await BnsHome.dir()).path, isolated);
    expect(Directory(isolated).existsSync(), isTrue,
        reason: 'the pinned home is created so the app just opens');
  });

  test('a pinned process never writes the shared pointer', () async {
    final isolated = p.join(root.path, 'harness-l3');
    BnsHome.applyStartupArgs(['--data-dir=$isolated']);
    // Even an in-app "move my home" writes no pointer while pinned.
    final elsewhere = Directory(p.join(root.path, 'elsewhere'))
      ..createSync(recursive: true);
    await BnsHome.setDir(elsewhere);
    expect((await BnsHome.dir()).path, elsewhere.path);
    final pointer = File(p.join(root.path, BnsHome.pointerFileName));
    expect(pointer.existsSync(), isFalse,
        reason: 'the live app\'s home is not the harness\'s to move');
  });

  test('a pinned process ignores the live pointer entirely', () async {
    // The live app once chose a custom home — its pointer exists.
    final liveHome = Directory(p.join(root.path, 'live-home'))
      ..createSync(recursive: true);
    File(p.join(root.path, BnsHome.pointerFileName))
        .writeAsStringSync(liveHome.path);

    final isolated = p.join(root.path, 'harness');
    BnsHome.applyStartupArgs(['--data-dir=$isolated']);
    expect((await BnsHome.dir()).path, isolated,
        reason: 'pinned wins; the live pointer is not even read');
  });

  test('no pin, no change: pointer behavior stays exactly as before',
      () async {
    expect((await BnsHome.dir()).path, root.path);
    final chosen = Directory(p.join(root.path, 'chosen'))
      ..createSync(recursive: true);
    await BnsHome.setDir(chosen);
    final pointer = File(p.join(root.path, BnsHome.pointerFileName));
    expect(pointer.existsSync(), isTrue);
    expect(pointer.readAsStringSync().trim(), chosen.path);
  });

  test('an empty or junk arg changes nothing', () async {
    BnsHome.applyStartupArgs(['--data-dir=', 'whatever', '--other=x']);
    expect((await BnsHome.dir()).path, root.path);
  });

  test('a dressed L2 Person .app uses sibling person/, not Documents',
      () async {
    final harness = Directory(p.join(root.path, '.l2-test'))
      ..createSync(recursive: true);
    final person = Directory(p.join(harness.path, 'person'))
      ..createSync(recursive: true);
    final exec = p.join(harness.path, 'BNS-L2.app', 'Contents', 'MacOS', 'bns');
    File(exec).createSync(recursive: true);

    expect(BnsHome.harnessHomeFromExecutable(exec), person.path);

    BnsHome.debugExecutableForTest = exec;
    BnsHome.applyStartupArgs(const []);
    expect((await BnsHome.dir()).path, person.path,
        reason: 'overlay + relaunch must open .l2-test/person, '
            'not the bundle Application Support');
  });

  test('a dressed Care .app uses sibling caregiver/', () {
    final harness = Directory(p.join(root.path, '.l2-test'))
      ..createSync(recursive: true);
    final care = Directory(p.join(harness.path, 'caregiver'))
      ..createSync(recursive: true);
    final exec =
        p.join(harness.path, 'BNS-Care.app', 'Contents', 'MacOS', 'bns');
    File(exec).createSync(recursive: true);
    expect(BnsHome.harnessHomeFromExecutable(exec), care.path);
  });

  test('stock /Applications/bns.app is not a harness', () {
    final exec = p.join(root.path, 'Applications', 'bns.app', 'Contents',
        'MacOS', 'bns');
    File(exec).createSync(recursive: true);
    expect(BnsHome.harnessHomeFromExecutable(exec), isNull);
  });

  test('--data-dir still wins over a harness sibling', () async {
    final harness = Directory(p.join(root.path, '.l3-test'))
      ..createSync(recursive: true);
    Directory(p.join(harness.path, 'person')).createSync();
    final exec =
        p.join(harness.path, 'BNS-Person.app', 'Contents', 'MacOS', 'bns');
    File(exec).createSync(recursive: true);
    BnsHome.debugExecutableForTest = exec;
    final elsewhere = p.join(root.path, 'elsewhere');
    BnsHome.applyStartupArgs(['--data-dir=$elsewhere']);
    expect((await BnsHome.dir()).path, elsewhere);
  });
}
