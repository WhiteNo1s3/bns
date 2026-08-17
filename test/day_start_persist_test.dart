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
    await BnsHome.setDir(home);
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(
        s.copyWith(dayStartHour: 0, dayRolloverHour: 5));
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
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

    await tester.ensureVisible(find.text('15:00'));
    await tester.tap(find.text('15:00'));
    await tester.pump();
    expect(picked, 15);
    await tester.runAsync(() async {
      await IsarService.persistDayStartHour(picked!);
      expect((await IsarService.getSettings()).dayStartHour, 15);
    });
  });
}
