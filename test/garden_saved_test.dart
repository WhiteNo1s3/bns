/// THE GARDEN IS SAVED (owner, 2026-08-16: "it should be saved for them
/// to remember"). Retention rolls only passing 'quick' notes off the
/// window; everything the person deliberately kept — 'remember' and
/// 'memorize' — stays, forever, including promoted mad-vents.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  QuickCapture old(String id, MemoryLevel level, {List<String> tags = const []}) =>
      QuickCapture(
        id: id,
        at: DateTime.now().subtract(const Duration(days: 40)),
        text: 'מלפני חודש וחצי',
        memoryLevel: level,
        tags: tags,
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_garden_test_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final home = Directory(p.join(root.path, 'home'))
      ..createSync(recursive: true);
    await IsarService.debugResetForTest();
    await BnsHome.setDir(home);
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('retention rolls quick notes off but never what the person kept',
      () async {
    await IsarService.addCapture(old('q', MemoryLevel.quick));
    await IsarService.addCapture(old('r', MemoryLevel.remember));
    await IsarService.addCapture(old('m', MemoryLevel.memorize));

    await IsarService.pruneOldData();

    final left = (await IsarService.getAllCaptures()).map((c) => c.id).toSet();
    expect(left.contains('q'), isFalse, reason: 'passing notes ride the window');
    expect(left.contains('r'), isTrue,
        reason: 'a chosen "remember" must not self-delete');
    expect(left.contains('m'), isTrue, reason: 'memorize is forever');
  });

  test('an old mad-vent burns out unless promoted to memorize', () async {
    await IsarService.addCapture(old('vent', MemoryLevel.remember,
        tags: const ['mad-vent']));
    await IsarService.addCapture(old('kept', MemoryLevel.memorize,
        tags: const ['mad-vent']));

    await IsarService.pruneOldData();

    final left = (await IsarService.getAllCaptures()).map((c) => c.id).toSet();
    expect(left.contains('vent'), isFalse,
        reason: 'anger gets space, not a permanent record');
    expect(left.contains('kept'), isTrue,
        reason: 'a promoted vent is a decision — respected');
  });
}
