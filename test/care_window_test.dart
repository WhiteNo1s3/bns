/// THE PER-LEVEL WALL — what leaves toward a helper is the level's window.
///
/// Owner, 2026-08-17: "the lan sync dumping full store instead of what it
/// has to." The law existed (`familyShareLevelFor`) with no sync callers;
/// these tests hold the new wall:
///
///  - the person's own devices still get the full day;
///  - a helper at level 1 gets opened asks ONLY — a skip, a mood, a vent
///    is never an ask;
///  - level 2 gets chosen family plans + family-tagged / need-help
///    routines (and their ✓ / skip logs) + family-tagged moments, vents
///    never, even tagged; untagged routines stay home;
///  - levels 3–4 get everything active, rants included (the law);
///  - EVERY window ships a settings stub — shareName + the person-day
///    clock and the wake on it; no identity, no keys: a hat cannot
///    travel inside a care window. 15:00 is the day, not a preference.
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
        careWindowFor(peerIsHelper: false, careLevel: 4, fullCareMode: true),
        isNull,
      );
      expect(
        careWindowFor(peerIsHelper: false, careLevel: 1, fullCareMode: false),
        isNull,
      );
    });

    test('a helper gets the level\'s window', () {
      expect(
        careWindowFor(peerIsHelper: true, careLevel: 1, fullCareMode: false),
        FamilyShareLevel.asksOnly,
      );
      expect(
        careWindowFor(peerIsHelper: true, careLevel: 2, fullCareMode: false),
        FamilyShareLevel.chosenFamily,
      );
      expect(
        careWindowFor(peerIsHelper: true, careLevel: 3, fullCareMode: true),
        FamilyShareLevel.fullCare,
      );
      expect(
        careWindowFor(peerIsHelper: true, careLevel: 4, fullCareMode: true),
        FamilyShareLevel.fullCare,
      );
    });
  });

  test('level 2 shares chosen and asked routines, never private ones', () {
    final now = DateTime(2026, 8, 17);
    Routine r(String id, List<String> tags) => Routine(
      id: id,
      title: id,
      recurrenceType: RecurrenceType.daily,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
    expect(level2ShareAllowsRoutine(r('fam', const ['family'])), isTrue);
    expect(level2ShareAllowsRoutine(r('ask', const ['need-help'])), isTrue);
    expect(level2ShareAllowsRoutine(r('priv', const [])), isFalse);
    expect(
      level2ShareAllowsRoutine(r('vent', const ['family', 'mad-vent'])),
      isFalse,
    );
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
    expect(
      TrustedDevice.fromJson(const {'id': 'x'}).peerIsHelper,
      isFalse,
      reason: 'older rows without the field mean "not known yet"',
    );
  });

  group('exportCareWindow — what is actually in the file', () {
    /// One store with every kind of thing a wall must judge.
    Future<void> seedStore() async {
      final now = DateTime(2026, 8, 16, 12);
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          shareName: 'Ben',
          dayStartHour: 15,
          dayRolloverHour: 5,
          wakeAlarmTime: '07:30',
          wakeAlarmNote: 'קפה'));
      await IsarService.addRoutine(
        Routine(
          id: 'r1',
          title: 'לקחת תרופות',
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await IsarService.addRoutine(
        Routine(
          id: 'r-family',
          title: 'כוס מים',
          recurrenceType: RecurrenceType.daily,
          time: '16:00',
          tags: const ['family'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await IsarService.addRoutine(
        Routine(
          id: 'r-ask',
          title: 'לסדר שולחן',
          recurrenceType: RecurrenceType.daily,
          time: '21:00',
          tags: const ['need-help'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await IsarService.logCompletion(
        routineId: 'r1',
        date: '2026-08-16',
        status: CompletionStatus.done,
      );
      await IsarService.logCompletion(
        routineId: 'r-family',
        date: '2026-08-16',
        status: CompletionStatus.skipped,
        reason: 'משהו הפריע',
      );
      await IsarService.addEvent(
        CalendarEvent(
          id: 'e-family',
          title: 'רופא שיניים',
          date: '2026-08-20',
          shareWithFamily: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await IsarService.addEvent(
        CalendarEvent(
          id: 'e-private',
          title: 'פגישה פרטית',
          date: '2026-08-21',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await IsarService.addCapture(
        QuickCapture(
          id: 'c-family',
          at: now,
          text: 'רגע משפחתי',
          tags: const ['family'],
          memoryLevel: MemoryLevel.remember,
        ),
      );
      await IsarService.addCapture(
        QuickCapture(
          id: 'c-plain',
          at: now,
          text: 'מחשבה פרטית',
          memoryLevel: MemoryLevel.remember,
        ),
      );
      // A vent that was even (wrongly) family-tagged must never leave
      // below full care.
      await IsarService.addCapture(
        QuickCapture(
          id: 'c-vent',
          at: now,
          text: 'מעצבן!!!',
          tags: const ['mad-vent', 'family'],
          memoryLevel: MemoryLevel.quick,
        ),
      );
      await IsarService.addCapture(
        buildAskedHelpCapture(
          id: 'c-ask',
          at: now,
          aboutTitle: 'לקחת תרופות',
          linkedRoutineId: 'r1',
          hebrew: true,
        ),
      );
    }

    test('level 1: opened asks only, and a settings stub', () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(FamilyShareLevel.asksOnly);
      final parsed = await BnsImporter.readBns(f);

      expect(parsed.captures.map((c) => c.id), [
        'c-ask',
      ], reason: 'a skip, a mood, a vent is never an ask');
      expect(parsed.events, isEmpty);
      expect(parsed.routines, isEmpty);
      expect(parsed.logs, isEmpty);
      expect(
        parsed.settings.deviceId,
        isEmpty,
        reason: 'a care window teaches nothing about the person\'s device',
      );
      expect(parsed.settings.effectiveShareName, 'Ben');
      expect(parsed.settings.careLockHash, isEmpty);
      expect(parsed.settings.dayStartHour, 15,
          reason: 'the person-day clock IS the day — it rides the window');
      expect(parsed.settings.dayRolloverHour, 5);
      expect(parsed.settings.wakeAlarmTime, '07:30',
          reason: 'their wake is on that clock — Care may see it');
    });

    test('level 2: chosen family + family moments, vents never', () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(
        FamilyShareLevel.chosenFamily,
      );
      final parsed = await BnsImporter.readBns(f);

      expect(parsed.events.map((e) => e.id), ['e-family']);
      final ids = parsed.captures.map((c) => c.id).toSet();
      expect(ids, {'c-family', 'c-ask'});
      expect(
        ids.contains('c-vent'),
        isFalse,
        reason: 'a rage-moment share decision must not outlive the rage',
      );
      expect(
        parsed.routines.map((r) => r.id).toSet(),
        {'r-family', 'r-ask'},
        reason: 'the chosen day travels — private untagged routines stay home',
      );
      expect(parsed.routines.map((r) => r.id), isNot(contains('r1')));
      expect(
        parsed.logs.map((l) => l.routineId).toSet(),
        {'r-family'},
        reason: 'a skip on a shared routine is what happened — it rides along',
      );
      expect(parsed.settings.deviceId, isEmpty);
    });

    test(
      'levels 3–4: everything active, rants included, still a stub',
      () async {
        await seedStore();
        final f = await BnsExporter.exportCareWindow(FamilyShareLevel.fullCare);
        final parsed = await BnsImporter.readBns(f);

        expect(parsed.routines.map((r) => r.id), contains('r1'));
        expect(parsed.logs, isNotEmpty);
        expect(parsed.events.length, 2);
        final ids = parsed.captures.map((c) => c.id).toSet();
        expect(
          ids.containsAll({'c-family', 'c-plain', 'c-vent', 'c-ask'}),
          isTrue,
          reason: 'full care: the frustration IS the signal',
        );
        expect(
          parsed.settings.deviceId,
          isEmpty,
          reason: 'even full care ships no identity, keys or preferences',
        );
        expect(parsed.settings.careLockHash, isEmpty);
      },
    );

    test(
      'an empty / subset window cannot wipe the person\'s routines',
      () async {
        await seedStore();
        final before = (await IsarService.getAllRoutines())
            .map((r) => r.id)
            .toSet();
        expect(before, containsAll({'r1', 'r-family', 'r-ask'}));
        // Receive-first from Care that has nothing (or only the window)
        // must ADD, never replace. Person's private r1 stays.
        final empty = await BnsExporter.exportCareWindow(
          FamilyShareLevel.asksOnly,
        );
        await BnsImporter.importMerge(empty);
        final afterEmpty = (await IsarService.getAllRoutines())
            .map((r) => r.id)
            .toSet();
        expect(
          afterEmpty.containsAll(before),
          isTrue,
          reason: 'Care-empty / receive-first must not wipe Person',
        );
        final subset = await BnsExporter.exportCareWindow(
          FamilyShareLevel.chosenFamily,
        );
        await BnsImporter.importMerge(subset);
        final afterSubset = (await IsarService.getAllRoutines())
            .map((r) => r.id)
            .toSet();
        expect(afterSubset.containsAll(before), isTrue);
      },
    );

    test('a care window cannot teach a hat on import', () async {
      await seedStore();
      final f = await BnsExporter.exportCareWindow(FamilyShareLevel.fullCare);
      final parsedSettings = await BnsImporter.importMerge(f);
      expect(
        parsedSettings.deviceId,
        isEmpty,
        reason: 'the learn guard (deviceId match) can never pass on a stub',
      );
    });

    test('Care learns 15:00 from the window; a 0 stub cannot eat it', () async {
      await seedStore();
      final window = await BnsExporter.exportCareWindow(
        FamilyShareLevel.chosenFamily,
      );
      // Pretend we are Care: midnight clock, helper hat.
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: true, dayStartHour: 0, dayRolloverHour: 0));
      await BnsImporter.importMerge(window);
      final learned = await IsarService.getSettings();
      expect(learned.dayStartHour, 15,
          reason: 'receive-first must teach Care the person\'s day start');
      expect(learned.dayRolloverHour, 5);
      expect(learned.wakeAlarmTime, '07:30',
          reason: 'Care may see the time on their clock');
      expect(learned.caregiverDevice, isTrue,
          reason: 'the clock travels; the hat does not');

      // An empty / default stub (the old shareName-only copy) must not
      // put 15 back to midnight.
      await BnsImporter.importMerge(
        await BnsExporter.exportCareWindow(FamilyShareLevel.asksOnly),
      );
      // asksOnly from THIS store now has 15 (we are Care, clock already
      // learned). Simulate the eater: a stub that never knew the field.
      await IsarService.mergeData(
        routines: [],
        events: [],
        captures: [],
        logs: [],
        incomingSettings: const AppSettings(),
      );
      final kept = await IsarService.getSettings();
      expect(kept.dayStartHour, 15);
      expect(kept.dayRolloverHour, 5);
      expect(kept.wakeAlarmTime, '07:30',
          reason: 'an empty stub cannot wipe a wake Care already holds');
    });
  });

  test('setTrustedDeviceHelper flips only the named row', () async {
    await IsarService.saveTrustedDevice(
      TrustedDevice(
        id: 'care-1',
        name: 'BNS Care',
        lastAddress: '',
        lastSyncedAt: DateTime(2026, 8, 17),
      ),
    );
    await IsarService.setTrustedDeviceHelper('care-1', true);
    expect(
      (await IsarService.getTrustedDevice('care-1'))!.peerIsHelper,
      isTrue,
    );
    await IsarService.setTrustedDeviceHelper('nobody', true);
    expect(await IsarService.getTrustedDevice('nobody'), isNull);
  });
}
