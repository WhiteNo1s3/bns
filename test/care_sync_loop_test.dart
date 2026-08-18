/// Closed LAN loop — Care updates the day; the person lives it.
///
/// Repro of the blob-merge bug: answering a plan bumped [updatedAt], so
/// last-write-wins treated the whole item as one. Either Care's Saturday
/// update wiped the ✓, or the ✓ hid the update. The person was then sent
/// to Settings to "wait for sync".
///
/// The law (docs/care-levels.md, AGENTS.md, owner 2026-08-18):
///   1–2 make their own day and future; Care ADDS / refreshes upcoming
///       facts so they are not shocked (cousin birthday Saturday).
///   3 can still make some changes (not a doll).
///   4 receives Care's built day; they only answer.
/// Happened stays theirs at every level. Auto-sync is trusted-only.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/care_lock.dart';
import 'package:bns/core/care_sync_merge.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/sync_policy.dart';
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

  final t0 = DateTime(2026, 8, 16, 10);
  final t1 = DateTime(2026, 8, 16, 11);
  final t2 = DateTime(2026, 8, 17, 9);
  final tAnswer = DateTime(2026, 8, 17, 18);

  CalendarEvent plan({
    String id = 'e-cousin',
    String title = 'יום הולדת לדודן',
    String date = '2026-08-22',
    DateTime? created,
    DateTime? updated,
    String? answer,
    DateTime? answerAt,
    bool family = false,
    List<GatherItem> gather = const [],
  }) =>
      CalendarEvent(
        id: id,
        title: title,
        date: date,
        time: '16:00',
        shareWithFamily: family,
        answer: answer,
        answerAt: answerAt,
        gather: gather,
        createdAt: created ?? t0,
        updatedAt: updated ?? t0,
      );

  Routine routine({
    String id = 'r-morning',
    String title = 'השגרה שלי',
    List<String> tags = const [],
    DateTime? created,
    DateTime? updated,
    Map<String, String> timeByDay = const {},
  }) =>
      Routine(
        id: id,
        title: title,
        recurrenceType: RecurrenceType.daily,
        time: '08:00',
        tags: tags,
        timeByDay: timeByDay,
        createdAt: created ?? t0,
        updatedAt: updated ?? t0,
      );

  AppSettings personAt(int level) {
    final guided = level >= 4;
    final full = level >= 3;
    return AppSettings(
      deviceId: 'person-1',
      deviceName: 'BNS Phone',
      caregiverDevice: false,
      careLevel: level,
      guidedMode: guided,
      fullCareMode: full,
      shareName: 'Ben',
    );
  }

  const helper = AppSettings(
    deviceId: 'care-1',
    deviceName: 'BNS Care',
    caregiverDevice: true,
    careLevel: 1,
    shareName: 'עוזרת',
  );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_care_loop_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final home = Directory(p.join(root.path, 'home'))
      ..createSync(recursive: true);
    await IsarService.debugResetForTest();
    await BnsHome.setDir(home);
    CareState.guided.value = false;
    CareState.caregiver.value = false;
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  group('the blob-merge failure (repro)', () {
    test('answering must not make the plan look newer than Care\'s edit',
        () async {
      await IsarService.addEvent(plan());
      await IsarService.answerEvent('e-cousin', 'done');
      final after = (await IsarService.getEventsForDate('2026-08-22')).single;
      expect(after.answer, 'done');
      expect(after.updatedAt, t0,
          reason: 'the ✓ is not a rebuild of Saturday');
      expect(after.answerAt, isNotNull);
    });

    test('old last-write-wins would hide Saturday or wipe the ✓', () {
      CalendarEvent lww(CalendarEvent a, CalendarEvent b) =>
          b.updatedAt.isAfter(a.updatedAt) ? b : a;

      final answered = plan(answer: 'done', answerAt: tAnswer, updated: tAnswer);
      final careEarlier = plan(title: 'יום הולדת לדודן — 16:00, להתכונן', updated: t2);
      final hidSaturday = lww(answered, careEarlier);
      expect(hidSaturday.answer, 'done');
      expect(hidSaturday.title, answered.title,
          reason: 'THE BUG: a later ✓ hid Care\'s Saturday update');

      final careLater = plan(title: 'יום הולדת לדודן — 16:00, להתכונן', updated: t2.add(const Duration(hours: 12)));
      final wipedTick = lww(answered, careLater);
      expect(wipedTick.title, careLater.title);
      expect(wipedTick.answer, isNull, reason: 'THE BUG: Care edit ate the ✓');
    });
  });

  group('level 1–2 — they own the day; Care refreshes the future', () {
    test('L1: Care adds cousin Saturday; their own routine stays theirs',
        () async {
      await IsarService.updateSettings(personAt(1));
      await IsarService.addRoutine(
        routine(updated: t1), // they set it
      );
      await IsarService.mergeData(
        routines: [
          routine(title: 'שגרת המלווה', updated: t2),
          routine(id: 'seed-1', title: 'CARE-SEED', updated: t2),
        ],
        events: [plan(title: 'יום הולדת לדודן — שבת', updated: t2)],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      final routines = await IsarService.getAllRoutines();
      expect(routines.where((r) => r.id == 'r-morning').single.title, 'השגרה שלי',
          reason: 'they set their routine — Care does not replace it');
      expect(
        routines.where((r) => r.id == 'seed-1').single.title,
        isNot('CARE-SEED'),
        reason: 'a helper seed must not overwrite the day they already have',
      );
      final events = await IsarService.getAllEvents();
      expect(events.single.title, 'יום הולדת לדודן — שבת',
          reason: 'Care-given upcoming fact arrives so they can live toward it');
    });

    test('L2: Care refreshes the family Saturday; private routine stays',
        () async {
      await IsarService.updateSettings(personAt(2));
      await IsarService.addEvent(plan(family: true, updated: t0));
      await IsarService.addRoutine(
        routine(id: 'r-private', title: 'ישיבה שקטה', updated: t1),
      );
      await IsarService.mergeData(
        routines: [
          routine(
            id: 'r-private',
            title: 'לא שלהם',
            updated: t2,
          ),
          routine(
            id: 'r-family',
            title: 'כוס מים ביחד',
            tags: const ['family'],
            updated: t2,
          ),
        ],
        events: [
          plan(
            title: 'יום הולדת לדודן — עדיין שבת, להתכונן',
            family: true,
            updated: t2,
          ),
        ],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      expect(
        (await IsarService.getEventsForDate('2026-08-22')).single.title,
        'יום הולדת לדודן — עדיין שבת, להתכונן',
        reason: 'the daily update so they are not shocked',
      );
      expect(
        (await IsarService.getAllRoutines())
            .where((r) => r.id == 'r-private')
            .single
            .title,
        'ישיבה שקטה',
      );
      expect(
        (await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-family'),
        reason: 'Care may GIVE a shared routine; they still own the private one',
      );
    });

    test('L1–2 stay off Settings — calendar is open so they can plan', () {
      CareState.guided.value = false;
      expect(CareState.containmentRedirect('/calendar'), isNull);
      expect(CareState.containmentRedirect('/tomorrow'), isNull);
    });
  });

  group('level 3 — they can still change things', () {
    test('a newer person edit of the plan holds; a newer Care edit lands',
        () async {
      await IsarService.updateSettings(personAt(3));
      await IsarService.addEvent(plan(title: 'שיניתי לבד', updated: t2));
      await IsarService.mergeData(
        routines: const [],
        events: [plan(title: 'גרסת המלווה הישנה', updated: t1)],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      expect(
        (await IsarService.getEventsForDate('2026-08-22')).single.title,
        'שיניתי לבד',
        reason: 'level 3 is not a doll',
      );

      await IsarService.mergeData(
        routines: const [],
        events: [plan(title: 'עדכון מהמלווה', updated: t2.add(const Duration(hours: 2)))],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      expect(
        (await IsarService.getEventsForDate('2026-08-22')).single.title,
        'עדכון מהמלווה',
      );
    });
  });

  group('level 4 — Care builds; they answer', () {
    test('Care plan lands and the ✓ they already gave stays', () async {
      await IsarService.updateSettings(personAt(4));
      await IsarService.addEvent(plan(updated: t0));
      await IsarService.answerEvent('e-cousin', 'done');
      await IsarService.mergeData(
        routines: [
          routine(id: 'r-care', title: 'תרופות הערב', updated: t2),
        ],
        events: [
          plan(
            title: 'יום הולדת לדודן — 16:00',
            updated: t2,
          ),
        ],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      final e = (await IsarService.getEventsForDate('2026-08-22')).single;
      expect(e.title, 'יום הולדת לדודן — 16:00');
      expect(e.answer, 'done', reason: 'THE PERSON ANSWERS — Care cannot wipe it');
      expect(
        (await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-care'),
      );
    });

    test('they can still answer after the Care day arrives', () async {
      await IsarService.updateSettings(personAt(4));
      await IsarService.mergeData(
        routines: [routine(id: 'r-new', title: 'כוס מים', updated: t2)],
        events: [plan(updated: t2)],
        captures: const [],
        logs: const [],
        incomingSettings: helper,
      );
      await IsarService.logCompletion(
        routineId: 'r-new',
        date: '2026-08-18',
        status: CompletionStatus.done,
      );
      await IsarService.answerEvent('e-cousin', 'done');
      expect(await IsarService.getLogsForDate('2026-08-18'), hasLength(1));
      expect(
        (await IsarService.getEventsForDate('2026-08-22')).single.answer,
        'done',
      );
    });

    test('guided stays on Today — Sync is not where they wait', () {
      CareState.guided.value = true;
      expect(CareState.containmentRedirect('/'), isNull);
      expect(CareState.containmentRedirect('/sync'), '/');
    });
  });

  group('answers and gather never fight the plan', () {
    test('take-back is a new answerAt, not a missing field', () async {
      await IsarService.addEvent(plan());
      await IsarService.answerEvent('e-cousin', 'done');
      await IsarService.answerEvent('e-cousin', null);
      final e = (await IsarService.getEventsForDate('2026-08-22')).single;
      expect(e.answer, isNull);
      expect(e.answerAt, isNotNull);
      expect(e.updatedAt, t0);
    });

    test('gather takenAt rides the person; Care can rebuild the bag', () {
      final local = plan(
        gather: [
          const GatherItem(id: 'g1', text: 'כרטיס'),
        ],
        answer: 'done',
        answerAt: tAnswer,
      );
      final taken = local.copyWith(gather: [
        GatherItem(id: 'g1', text: 'כרטיס', takenAt: tAnswer),
      ]);
      final careBag = plan(
        updated: t2,
        gather: const [
          GatherItem(id: 'g1', text: 'כרטיס'),
          GatherItem(id: 'g2', text: 'מתנה'),
        ],
      );
      final merged = mergeDirectedEvent(
        local: taken,
        incoming: careBag,
        incomingFromHelper: true,
        band: PersonCareBand.guided,
      );
      expect(merged.gather.map((g) => g.id), ['g1', 'g2']);
      expect(merged.gather.first.takenAt, tAnswer);
      expect(merged.gather.last.takenAt, isNull);
      expect(merged.answer, 'done');
    });

    test('helper logs cannot restore a take-back on the person', () async {
      await IsarService.updateSettings(personAt(3));
      await IsarService.addRoutine(routine(id: 'r1'));
      await IsarService.logCompletion(
        routineId: 'r1',
        date: '2026-08-18',
        status: CompletionStatus.done,
      );
      await IsarService.removeCompletion(routineId: 'r1', date: '2026-08-18');
      expect(await IsarService.getLogsForDate('2026-08-18'), isEmpty);
      await IsarService.mergeData(
        routines: const [],
        events: const [],
        captures: const [],
        logs: [
          CompletionLog(
            id: 'stale',
            routineId: 'r1',
            date: '2026-08-18',
            status: CompletionStatus.done,
            at: t1,
          ),
        ],
        incomingSettings: helper,
      );
      expect(await IsarService.getLogsForDate('2026-08-18'), isEmpty);
    });
  });

  group('authorized doors only', () {
    test('untrusted never auto-syncs and never gets a change-push', () {
      expect(
        shouldAutoSyncOnSight(
          autoSyncEnabled: true,
          trusted: false,
          lanAllowed: true,
          lastAutoSyncAt: null,
          now: t2,
        ),
        isFalse,
      );
      expect(
        shouldPushChangeToTrusted(
          autoSyncEnabled: true,
          trusted: false,
          lanAllowed: true,
        ),
        isFalse,
      );
    });

    test('TrustedDevice remembers the last TCP door', () {
      final t = TrustedDevice(
        id: 'care-1',
        name: 'BNS Care',
        lastAddress: '192.168.31.7',
        lastPort: 42427,
        lastSyncedAt: t2,
      );
      expect(TrustedDevice.fromJson(t.toJson()).lastPort, 42427);
      expect(
        TrustedDevice.fromJson(const {'id': 'x', 'lastAddress': '1.2.3.4'})
            .lastPort,
        42425,
      );
    });
  });
}
