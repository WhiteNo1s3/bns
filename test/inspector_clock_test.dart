/// THE INSPECTOR'S HAND ON THE CLOCK — and the picker without the wall.
///
/// Owner, 2026-08-18: level 3–4 "are not really feeling time the same
/// as regular humans" — the caregiver holds their clock. These tests
/// hold the rule to its edges: a helper's CHOSEN hour reaches a person
/// under full care/guided only; a helper's 0 is never a choice; outside
/// full care the person's clock is theirs alone. And the fusion sheet
/// picks a time with a rail and one confirm — no ninety-six rows.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('adoptPersonDayHour — the inspector\'s hand', () {
    test('a helper\'s chosen hour reaches a full-care person', () {
      expect(
          adoptPersonDayHour(
              incoming: 15,
              local: 0,
              incomingIsHelper: true,
              localUnderFullCare: true),
          15);
      expect(
          adoptPersonDayHour(
              incoming: 16,
              local: 15,
              incomingIsHelper: true,
              localUnderFullCare: true),
          16,
          reason: 'the inspector may also CHANGE a set clock at 3–4');
    });

    test('a helper\'s 0 is never a choice', () {
      expect(
          adoptPersonDayHour(
              incoming: 0,
              local: 15,
              incomingIsHelper: true,
              localUnderFullCare: true),
          15);
    });

    test('outside full care the person\'s clock is theirs alone', () {
      expect(
          adoptPersonDayHour(
              incoming: 15,
              local: 0,
              incomingIsHelper: true,
              localUnderFullCare: false),
          0);
    });

    test('person↔person stays exactly as it was', () {
      expect(adoptPersonDayHour(incoming: 15, local: 0), 15);
      expect(adoptPersonDayHour(incoming: 0, local: 15), 15);
      expect(adoptPersonDayHour(incoming: 16, local: 15), 16);
    });
  });

  group('mergeData carries the inspector\'s clock', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('bns_clock_test_');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      await BnsHome.setDir(home);
    });

    tearDown(() async {
      await IsarService.debugResetForTest();
      BnsHome.debugClearForcedForTest();
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });

    Future<void> merge(AppSettings incoming) => IsarService.mergeData(
        routines: [],
        events: [],
        captures: [],
        logs: [],
        incomingSettings: incoming);

    test('a guided person adopts the helper\'s chosen clock', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          guidedMode: true, fullCareMode: true, careLevel: 4));
      final helper = (await IsarService.getSettings()).copyWith(
          deviceId: 'care-1',
          caregiverDevice: true,
          guidedMode: false,
          dayStartHour: 15,
          dayRolloverHour: 5);
      await merge(helper);
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15);
      expect(after.dayRolloverHour, 5);
      expect(after.guidedMode, isTrue, reason: 'the cage stays shut');
    });

    test('a level-1 person\'s clock ignores the helper entirely', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(dayStartHour: 15));
      final helper = (await IsarService.getSettings()).copyWith(
          deviceId: 'care-1',
          caregiverDevice: true,
          dayStartHour: 9,
          dayRolloverHour: 3);
      await merge(helper);
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15);
      expect(after.dayRolloverHour, 0);
    });
  });

  group('the fusion sheet — a time without the wall', () {
    testWidgets('rail picks the hour, one confirm wears it', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showTimeFusionSheet(
                  context: context,
                  title: 'מתי היום שלך מתחיל?',
                  initial: const TimeOfDay(hour: 8, minute: 0),
                  quarters: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('08:00', findRichText: true), findsWidgets);
      await tester.tap(find.text('10:00').first);
      await tester.pump();
      await tester.tap(find.textContaining('לקבוע'));
      await tester.pumpAndSettle();

      expect(picked, const TimeOfDay(hour: 10, minute: 0));
    });

    testWidgets('the ±15 steps move by quarters and confirm', (tester) async {
      TimeOfDay? picked;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showTimeFusionSheet(
                  context: context,
                  title: 'שעה',
                  initial: const TimeOfDay(hour: 10, minute: 0),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('+15'));
      await tester.pump();
      await tester.tap(find.textContaining('+15'));
      await tester.pump();
      await tester.tap(find.textContaining('−15'));
      await tester.pump();
      await tester.tap(find.textContaining('לקבוע'));
      await tester.pumpAndSettle();

      expect(picked, const TimeOfDay(hour: 10, minute: 15));
    });
  });
}
