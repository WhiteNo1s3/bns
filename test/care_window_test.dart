/// THE PER-LEVEL WALL — what leaves toward a helper is the level's window.
///
/// Owner, 2026-08-17: "the lan sync dumping full store instead of what it
/// has to." The law existed (`familyShareLevelFor`) with no sync callers;
/// these tests hold the new wall:
///
///  - the person's own devices still get the full day;
///  - a helper at level 1 gets opened asks ONLY — a skip, a mood, a vent
///    is never an ask;
///  - level 2 gets chosen family plans + family-tagged moments, vents
///    never, even tagged;
///  - levels 3–4 get everything active, rants included (the law);
///  - EVERY window ships a settings stub — shareName only, no identity,
///    no keys: a hat cannot travel inside a care window.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/core/need_help.dart';
import 'package:bns/core/sync_policy.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_care_window_test_');
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

  group('careWindowFor — the wall decision', () {
    test('own devices always get the full day', () {
      expect(
          careWindowFor(
              peerIsHelper: false, careLevel: 4, fullCareMode: true),
          isNull);
      expect(
          careWindowFor(
              peerIsHelper: false, careLevel: 1, fullCareMode: false),
          isNull);
    });

    test('a helper gets the level\'s window', () {
      expect(
          careWindowFor(
              peerIsHelper: true, careLevel: 1, fullCareMode: false),
          FamilyShareLevel.asksOnly);
      expect(
          careWindowFor(
              peerIsHelper: true, careLevel: 2, fullCareMode: false),
          FamilyShareLevel.chosenFamily);
      expect(
          careWindowFor(
              peerIsHelper: true, careLevel: 3, fullCareMode: true),
          FamilyShareLevel.fullCare);
      expect(
          careWindowFor(
              peerIsHelper: true, careLevel: 4, fullCareMode: true),
          FamilyShareLevel.fullCare);
    });
  });

  test('TrustedDevice remembers the helper hat through json', () {
    final t = TrustedDevice(
      id: 'care-1',
      name: 'BNS Care',
      lastAddress: '192.168.31.7',
      lastSyncedAt: DateTime(2026, 8, 17),
      peerIsHelper: true,
    );
    final back = TrustedDevice.fromJson(t.toJson());
    expect(back.peerIsHelper, isTrue);
    expect(TrustedDevice.fromJson(const {'id': 'x'}).peerIsHelper, isFalse,
        reason: 'older rows without the field mean "not known yet"');
  });

  group('exportCareWindow — what is actually in the file', () {
    /// One store with every kind of thing a wall must judge.
    Future<void> seedStore() async {
      final now = DateTime(2026, 8, 16, 12);
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(shareName: 'Ben'));
      await IsarService.addRoutine(Routine(
        id: 'r1',
        title: 'לקחת תרופות',
        recurrenceType: RecurrenceType.daily,
        time: '08:00',
        createdAt: now,
        updatedAt: now,
      ));
      await IsarService.logCompletion(
          routineId: 'r1',
          date: '2026-08-16',
          status: CompletionStatus.done);
      await IsarService.addEvent(CalendarEvent(
        id: 'e-family',
        title: 'רופא שיניים',
        date: '2026-08-20',
        shareWithFamily: true,
        createdAt: now,
        updatedAt: now,
      ));
      await IsarService.addEvent(CalendarEvent(
        id: 'e-private',
        title: 'פגישה פרטית',
        date: '2026-08-21',
        createdAt: now,
        updatedAt: now,
      ));
      await IsarService.addCapture(QuickCapture(
        id: 'c-family',
        at: now,
        text: 'רגע משפחתי',
        tags: const ['family'],
        memoryLevel: MemoryLevel.remember,
      ));
      await IsarService.addCapture(QuickCapture(
        id: 'c-plain',
        at: now,
        text: 'מחשבה פרטית',
        memoryLevel: MemoryLevel.remember,
      ));
      // A vent that was even (wrongly) family-tagged must never leave
      // below full care.
      await IsarService.addCapture(QuickCapture(
        id: 'c-vent',
        at: now,
        text: 'מעצבן!!!',
        tags: const ['mad-vent', 'family'],
        memoryLevel: MemoryLevel.quick,
      ));
      await IsarService.addCapture(buildAskedHelpCapture(
        id: 'c-ask',
        at: now,
        aboutTitle: 'לקחת תרופות',
        linkedRoutineId: 'r1',
        hebrew: true,
      ));
    }

    test('level 1: opened asks only, and a settings stub', () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(FamilyShareLevel.asksOnly);
      final parsed = await BnsImporter.readBns(f);

      expect(parsed.captures.map((c) => c.id), ['c-ask'],
          reason: 'a skip, a mood, a vent is never an ask');
      expect(parsed.events, isEmpty);
      expect(parsed.routines, isEmpty);
      expect(parsed.logs, isEmpty);
      expect(parsed.settings.deviceId, isEmpty,
          reason: 'a care window teaches nothing about the person\'s device');
      expect(parsed.settings.effectiveShareName, 'Ben');
      expect(parsed.settings.careLockHash, isEmpty);
    });

    test('level 2: chosen family + family moments, vents never', () async {
      await seedStore();
      final f =
          await BnsExporter.exportCareWindow(FamilyShareLevel.chosenFamily);
      final parsed = await BnsImporter.readBns(f);

      expect(parsed.events.map((e) => e.id), ['e-family']);
      final ids = parsed.captures.map((c) => c.id).toSet();
      expect(ids, {'c-family', 'c-ask'});
      expect(ids.contains('c-vent'), isFalse,
          reason: 'a rage-moment share decision must not outlive the rage');
      expect(parsed.routines, isEmpty);
      expect(parsed.logs, isEmpty);
      expect(parsed.settings.deviceId, isEmpty);
    });

    test('levels 3–4: everything active, rants included, still a stub',
        () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(FamilyShareLevel.fullCare);
      final parsed = await BnsImporter.readBns(f);

      expect(parsed.routines.map((r) => r.id), contains('r1'));
      expect(parsed.logs, isNotEmpty);
      expect(parsed.events.length, 2);
      final ids = parsed.captures.map((c) => c.id).toSet();
      expect(ids.containsAll({'c-family', 'c-plain', 'c-vent', 'c-ask'}),
          isTrue,
          reason: 'full care: the frustration IS the signal');
      expect(parsed.settings.deviceId, isEmpty,
          reason: 'even full care ships no identity, keys or preferences');
      expect(parsed.settings.careLockHash, isEmpty);
    });

    test('a care window cannot teach a hat on import', () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(FamilyShareLevel.fullCare);
      final parsedSettings = await BnsImporter.importMerge(f);
      expect(parsedSettings.deviceId, isEmpty,
          reason: 'the learn guard (deviceId match) can never pass on a stub');
    });
  });

  test('setTrustedDeviceHelper flips only the named row', () async {
    await IsarService.saveTrustedDevice(TrustedDevice(
      id: 'care-1',
      name: 'BNS Care',
      lastAddress: '',
      lastSyncedAt: DateTime(2026, 8, 17),
    ));
    await IsarService.setTrustedDeviceHelper('care-1', true);
    expect((await IsarService.getTrustedDevice('care-1'))!.peerIsHelper,
        isTrue);
    await IsarService.setTrustedDeviceHelper('nobody', true);
    expect(await IsarService.getTrustedDevice('nobody'), isNull);
  });
}
