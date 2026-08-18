/// Unset 0 must not become 15 unless they tap a chip.
///
/// Lived 2026-08-17 ~23:57 IDT: isolated L2 Person on Today, no tap,
/// no הגדרות, caregiver did not write. dayStartHour went 0 → 15 and
/// auto-sync taught Care. Ranking may assume a 15:00 hole once evening
/// has begun. It must not persist. The Today door writes only on an
/// explicit hour-chip tap. First paint / no tap ⇒ still 0.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/day_items.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/day_start_door.dart';

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
    L.lang = 'he';
    root = await Directory.systemTemp.createTemp('bns_day_start_persist_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final home = Directory(p.join(root.path, 'home'))
      ..createSync(recursive: true);
    await IsarService.debugResetForTest();
    BnsHome.debugClearForcedForTest();
    await BnsHome.setDir(home);
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(
        s.copyWith(dayStartHour: 0, dayRolloverHour: 5));
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    BnsHome.debugClearForcedForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  final late = DateTime(2026, 8, 17, 23, 57);

  Routine r(String id, String? time) => Routine(
        id: id,
        title: 'R $id',
        recurrenceType: RecurrenceType.daily,
        time: time,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  test('evening ranking with unset 0 does not persist 15', () async {
    expect((await IsarService.getSettings()).dayStartHour, 0);
    expect(nextHoleStartHour(0, late, 5), 15);
    expect(
      isNextMorningSlot(
        usualHhmm: '07:45',
        todayHhmm: '21:45',
        now: late,
        startHour: 0,
        rolloverHour: 5,
      ),
      isTrue,
    );
    weaveDayList(
      routines: [r('morn', '07:45'), r('eve', '19:00')],
      plans: const [],
      doneRoutineIds: const {},
      skippedRoutineIds: const {},
      nextFirst: true,
      now: late,
      rolloverHour: 5,
      startHour: 0,
    );
    expect((await IsarService.getSettings()).dayStartHour, 0,
        reason: 'a virtual 15:00 hole must not write the store');
  });

  testWidgets('first paint of the Today door does not persist 15',
      (tester) async {
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 0,
          onPicked: (h) {
            picked = h;
            IsarService.persistDayStartHour(h);
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('מתי היום שלך מתחיל?'), findsOneWidget);
    expect(picked, isNull);
    await tester.runAsync(() async {
      expect((await IsarService.getSettings()).dayStartHour, 0,
          reason: 'no tap ⇒ still 0');
    });
  });

  testWidgets('tap 15 persists; no tap stays 0', (tester) async {
    // The chip wall became the fusion sheet (2026-08-18): the door
    // opens it, the rail names the hour, ONE confirm writes — the
    // self-write guard holds the same as before.
    int? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DayStartDoor(
          dayStartHour: 0,
          onPicked: (h) => picked = h,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    await tester.runAsync(() async {
      expect((await IsarService.getSettings()).dayStartHour, 0);
    });

    await tester.tap(find.text('מתי היום שלך מתחיל?'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.text('15:00'),
        find.byType(ListView), const Offset(0, -52));
    await tester.tap(find.text('15:00'));
    await tester.pump();
    expect(picked, isNull,
        reason: 'the rail alone writes nothing — only the confirm door');
    await tester.tap(find.textContaining('לקבוע'));
    await tester.pumpAndSettle();
    expect(picked, 15);
    await tester.runAsync(() async {
      await IsarService.persistDayStartHour(picked!);
      expect((await IsarService.getSettings()).dayStartHour, 15);
    });
  });

  testWidgets('store 15: Today door shows set words, never the question',
      (tester) async {
    await tester.runAsync(() async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(dayStartHour: 15));
    });

    await tester.pumpWidget(const MaterialApp(home: _TodayClockDoor()));
    // First paint may still be 0 — refresh must not leave the question
    // sitting on a loaded 15.
    await tester.pumpAndSettle();
    expect(find.text('מתי היום שלך מתחיל?'), findsNothing);
    expect(find.textContaining('היום מתחיל 15:00'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await IsarService.getSettings()).dayStartHour, 15,
          reason: 'refresh must not auto-write; 15 was already chosen');
    });
  });

  testWidgets('store 0: Today door stays the question', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _TodayClockDoor()));
    await tester.pumpAndSettle();
    expect(find.text('מתי היום שלך מתחיל?'), findsOneWidget);
    expect(find.textContaining('היום מתחיל'), findsNothing);
  });

  testWidgets('L2 Person disk 15 is the door; Documents 0 is not',
      (tester) async {
    // Lived 2026-08-18 ~19:16: .l2-test/person had 15, the running
    // bundle opened Application Support (0) and asked the question.
    late Directory harness;
    await tester.runAsync(() async {
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      harness = Directory(p.join(root.path, '.l2-test'))
        ..createSync(recursive: true);
      final person = Directory(p.join(harness.path, 'person'))
        ..createSync();
      File(p.join(person.path, 'bns_data.json')).writeAsStringSync(
        '{"version":1,"seeded":true,"cleanExit":true,'
        '"settings":{"dayStartHour":15,"dayRolloverHour":5},'
        '"routines":[],"events":[],"captures":[],"logs":[],'
        '"trusted":[],"stepProgress":{}}',
      );
      File(p.join(root.path, 'bns_data.json')).writeAsStringSync(
        '{"version":1,"seeded":true,"cleanExit":true,'
        '"settings":{"dayStartHour":0,"dayRolloverHour":5},'
        '"routines":[],"events":[],"captures":[],"logs":[],'
        '"trusted":[],"stepProgress":{}}',
      );
      final exec =
          p.join(harness.path, 'BNS-L2.app', 'Contents', 'MacOS', 'bns');
      File(exec).createSync(recursive: true);
      BnsHome.debugExecutableForTest = exec;
      BnsHome.applyStartupArgs(const []);
      await IsarService.debugResetForTest();
    });

    expect((await tester.runAsync(() => IsarService.getSettings()))!.dayStartHour,
        15,
        reason: 'the running Person must read .l2-test/person, not Documents');

    await tester.pumpWidget(const MaterialApp(home: _TodayClockDoor()));
    await tester.pumpAndSettle();
    expect(find.text('מתי היום שלך מתחיל?'), findsNothing);
    expect(find.textContaining('היום מתחיל 15:00'), findsOneWidget);
  });
}

/// Today's clock bind: field starts at 0, then getSettings paints the door.
/// The real screen does the same in _loadUserAdapt / _refreshDoneToday.
class _TodayClockDoor extends StatefulWidget {
  const _TodayClockDoor();

  @override
  State<_TodayClockDoor> createState() => _TodayClockDoorState();
}

class _TodayClockDoorState extends State<_TodayClockDoor> {
  int _dayStartHour = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await IsarService.getSettings();
    if (!mounted) return;
    setState(() => _dayStartHour = settings.dayStartHour);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DayStartDoor(
        dayStartHour: _dayStartHour,
        onPicked: (h) async {
          await IsarService.persistDayStartHour(h);
          if (mounted) setState(() => _dayStartHour = h);
        },
      ),
    );
  }
}
