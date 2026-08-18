/// CARE ALARM — one time, every person this seat helps, on THEIR clock.
///
/// Held here:
///  - helper empty never wipes; L1–2 keep a wake they set; L3–4 adopt;
///  - each profile gets its own copy;
///  - a helper device still does not ring;
///  - untrusted doors never get a change-push;
///  - merge does not wipe a ✓;
///  - Care home names the door.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/care_alarm.dart';
import 'package:bns/core/care_sync_merge.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/reminder_plan.dart';
import 'package:bns/core/sync_policy.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/care_profiles.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/caregiver/care_alarm_door.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('adoptWake — the helper\'s hand on their clock', () {
    test('a helper\'s empty is never a choice', () {
      expect(
        adoptWakeAlarm(
          incoming: '',
          local: '07:30',
          incomingIsHelper: true,
          localUnderFullCare: true,
        ),
        '07:30',
      );
    });

    test('level 4 takes the helper\'s set time as an instruction', () {
      expect(
        adoptWakeAlarm(
          incoming: '08:00',
          local: '07:30',
          incomingIsHelper: true,
          localUnderFullCare: true,
        ),
        '08:00',
      );
    });

    test('level 1–2 keep a wake they already set', () {
      expect(
        adoptWakeAlarm(
          incoming: '08:00',
          local: '07:30',
          incomingIsHelper: true,
          localUnderFullCare: false,
        ),
        '07:30',
      );
    });

    test('level 1–2 with an empty nightstand may live toward it', () {
      expect(
        adoptWakeAlarm(
          incoming: '08:00',
          local: '',
          incomingIsHelper: true,
          localUnderFullCare: false,
        ),
        '08:00',
      );
    });

    test('time and note travel together', () {
      final kept = adoptWakeFields(
        incomingTime: '08:00',
        incomingNote: 'מהמלווה',
        localTime: '07:30',
        localNote: 'שלי',
        incomingIsHelper: true,
        localUnderFullCare: false,
      );
      expect(kept.time, '07:30');
      expect(kept.note, 'שלי');
    });
  });

  group('the helper never rings', () {
    test('planReminders stays empty on a Care seat even with a wake', () {
      final now = DateTime(2026, 8, 18, 7);
      final plan = planReminders(
        routines: [
          Routine(
            id: 'r1',
            title: 'בוקר',
            recurrenceType: RecurrenceType.daily,
            time: '08:00',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        events: const [],
        settings: const AppSettings(
          caregiverDevice: true,
          notificationsEnabled: true,
          wakeAlarmTime: '08:00',
        ),
        now: now,
      );
      expect(plan, isEmpty,
          reason: 'reminders never ring in the helper\'s pocket');
    });

    test('untrusted doors never get a change-push', () {
      expect(
        shouldPushChangeToTrusted(
          autoSyncEnabled: true,
          trusted: false,
          lanAllowed: true,
        ),
        isFalse,
      );
    });
  });

  group('merge does not wipe a ✓', () {
    test('Care\'s alarm-adjacent plan refresh keeps the person\'s answer', () {
      final t0 = DateTime(2026, 8, 16, 10);
      final tAnswer = DateTime(2026, 8, 17, 18);
      final t2 = DateTime(2026, 8, 17, 9);
      final local = CalendarEvent(
        id: 'e-cousin',
        title: 'יום הולדת לדודן',
        date: '2026-08-22',
        time: '16:00',
        answer: 'done',
        answerAt: tAnswer,
        createdAt: t0,
        updatedAt: t0,
      );
      final care = local.copyWith(
        title: 'יום הולדת לדודן — 16:00',
        answer: null,
        answerAt: null,
        updatedAt: t2,
      );
      final merged = mergeDirectedEvent(
        local: local,
        incoming: care,
        incomingFromHelper: true,
        band: PersonCareBand.independent,
      );
      expect(merged.answer, 'done');
      expect(merged.answerAt, tAnswer);
    });
  });

  group('each profile gets its own copy', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bns_care_alarm_');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      await BnsHome.setDir(home);
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(
        s.copyWith(caregiverDevice: true, shareName: 'מלווה'),
      );
    });

    tearDown(() async {
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    test('writeWakeToAll lands in every door, not only the sitting', () async {
      final dana = await CareProfiles.create('דנה');
      final yossi = await CareProfiles.create('יוסי');
      await CareProfiles.enter(dana);
      await IsarService.updateSettings(
        (await IsarService.getSettings()).copyWith(wakeAlarmTime: '06:00'),
      );

      await CareProfiles.writeWakeToAll(time: '08:00', note: 'בוקר');

      final sitting = await IsarService.getSettings();
      expect(sitting.wakeAlarmTime, '08:00');
      expect(sitting.wakeAlarmNote, 'בוקר');
      expect(sitting.caregiverDevice, isTrue,
          reason: 'the seat keeps the helper hat');

      final yossiRaw = jsonDecode(
        await File(
          '${(await CareProfiles.profileDir(yossi.id)).path}/bns_data.json',
        ).readAsString(),
      ) as Map;
      expect(yossiRaw['settings']['wakeAlarmTime'], '08:00');
      expect(yossiRaw['settings']['wakeAlarmNote'], 'בוקר');

      final seats = await CareProfiles.alarmSeats();
      expect(seats.map((e) => e.name), containsAll(['דנה', 'יוסי']));
      expect(seats.every((e) => e.wakeTime == '08:00'), isTrue);
    });

    test('a level-1 person keeps their wake across a helper merge', () async {
      await IsarService.updateSettings(
        (await IsarService.getSettings()).copyWith(
          caregiverDevice: false,
          careLevel: 1,
          wakeAlarmTime: '07:30',
          wakeAlarmNote: 'שלי',
        ),
      );
      await IsarService.mergeData(
        routines: const [],
        events: const [],
        captures: const [],
        logs: const [],
        incomingSettings: const AppSettings(
          deviceId: 'care-1',
          caregiverDevice: true,
          wakeAlarmTime: '08:00',
          wakeAlarmNote: 'מהמלווה',
        ),
      );
      final after = await IsarService.getSettings();
      expect(after.wakeAlarmTime, '07:30');
      expect(after.wakeAlarmNote, 'שלי');
      expect(after.caregiverDevice, isFalse);
    });

    test('a guided person adopts the helper\'s set wake', () async {
      await IsarService.updateSettings(
        (await IsarService.getSettings()).copyWith(
          caregiverDevice: false,
          careLevel: 4,
          guidedMode: true,
          fullCareMode: true,
          wakeAlarmTime: '',
        ),
      );
      await IsarService.mergeData(
        routines: const [],
        events: const [],
        captures: const [],
        logs: const [],
        incomingSettings: const AppSettings(
          deviceId: 'care-1',
          caregiverDevice: true,
          wakeAlarmTime: '08:00',
          wakeAlarmNote: 'היום מחכה',
        ),
      );
      final after = await IsarService.getSettings();
      expect(after.wakeAlarmTime, '08:00');
      expect(after.wakeAlarmNote, 'היום מחכה');
      expect(after.guidedMode, isTrue, reason: 'the cage stays shut');
    });
  });

  group('Care home names the door', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bns_care_alarm_ui_');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      await BnsHome.setDir(home);
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(
        s.copyWith(caregiverDevice: true, shareName: 'מלווה'),
      );
    });

    tearDown(() async {
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    testWidgets('the labeled door lists who will hear it', (tester) async {
      L.lang = 'he';
      await tester.runAsync(() async {
        await CareProfiles.create('דנה');
        await CareProfiles.create('יוסי');
      });
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openCareAlarmDoor(context),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final ctx = tester.element(find.text('open'));
        // Do not await — the door's future completes only when the sheet closes.
        openCareAlarmDoor(ctx);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();

      expect(find.text('צלצול לכולם'), findsOneWidget);
      expect(
        find.textContaining('המכשיר הזה לא מצלצל'),
        findsWidgets,
        reason: 'the helper\'s pocket is named as quiet',
      );
      expect(find.textContaining('דנה'), findsWidgets);
      expect(find.textContaining('יוסי'), findsWidgets);
      expect(find.text('לשלוח'), findsOneWidget);
    });
  });

  group('seat lines name their clock', () {
    test('paired, same time', () {
      L.lang = 'he';
      expect(
        careAlarmSeatLine(
          seat: const CareAlarmSeat(
            profileId: 'd',
            name: 'דנה',
            wakeTime: '08:00',
            paired: true,
          ),
          sentTime: '08:00',
          t: (en, he) => he,
        ),
        'דנה — 08:00 על השעון שלהם.',
      );
    });

    test('they already have another wake', () {
      L.lang = 'he';
      expect(
        careAlarmSeatLine(
          seat: const CareAlarmSeat(
            profileId: 'y',
            name: 'יוסי',
            wakeTime: '07:30',
            paired: true,
          ),
          sentTime: '08:00',
          t: (en, he) => he,
        ),
        contains('07:30'),
      );
    });
  });
}
