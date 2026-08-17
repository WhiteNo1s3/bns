/// THE HELPER IS NEVER THE GUIDED ONE — and hats never travel.
///
/// Owner, 2026-08-17: "the caregiver becomes level 4 user — this is not
/// acceptable." Two walls, both held here:
///
///  1. The door-frame rule (level-4 containment) never applies to a
///     helper's device — even while a store contaminated by the pre-fix
///     merges still claims guidedMode. And a contaminated store HEALS on
///     load, so the claim itself goes away.
///  2. Care flags cross only between the person's own devices. A helper
///     keeps its own hat through merge; a person pulling a Care store
///     never adopts the helper's hat — adopting guidedMode=false from
///     Care would silently open the level-4 cage.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/care_lock.dart';
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

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_containment_test_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final home = Directory(p.join(root.path, 'home'))
      ..createSync(recursive: true);
    await IsarService.debugResetForTest();
    await BnsHome.setDir(home);
    CareState.guided.value = false;
    CareState.caregiver.value = false;
    CareState.relock();
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    CareState.guided.value = false;
    CareState.caregiver.value = false;
    CareState.relock();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  group('the door-frame rule', () {
    test('a guided person is contained to the day and the telling door', () {
      CareState.guided.value = true;
      expect(CareState.containmentRedirect('/'), isNull);
      expect(CareState.containmentRedirect('/capture'), isNull);
      expect(CareState.containmentRedirect('/routines'), '/');
      expect(CareState.containmentRedirect('/calendar'), '/');
      expect(CareState.containmentRedirect('/menu'), '/');
      expect(CareState.containmentRedirect('/sync'), '/');
    });

    test('a helper walks free, whatever a contaminated store claims', () {
      CareState.guided.value = true; // stale contamination, pre-heal
      CareState.caregiver.value = true;
      expect(CareState.containmentRedirect('/routines'), isNull,
          reason: 'building the day is the inspector\'s work');
      expect(CareState.containmentRedirect('/calendar'), isNull);
      expect(CareState.containmentRedirect('/menu'), isNull);
    });

    test('an unlocked caregiver sitting opens the rooms, then relocks', () {
      CareState.guided.value = true;
      CareState.noteUnlocked();
      expect(CareState.containmentRedirect('/routines'), isNull);
      CareState.relock();
      expect(CareState.containmentRedirect('/routines'), '/');
    });
  });

  group('hats never travel', () {
    test('a contaminated Care store heals on load', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: true, guidedMode: true, careLevel: 4));
      // Relaunch: cache dropped, same store file read back in.
      await IsarService.debugResetForTest();
      final after = await IsarService.getSettings();
      expect(after.caregiverDevice, isTrue);
      expect(after.guidedMode, isFalse,
          reason: 'guided is the shape of the person\'s day, '
              'never of the inspector\'s copy');
    });

    test('the helper keeps its own hat through merge, guided healed',
        () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: true,
          guidedMode: true, // adopt-era contamination
          shareName: 'עוזרת',
          careLockHash: 'salt:care-key'));
      final person = (await IsarService.getSettings()).copyWith(
          deviceId: 'person-1',
          deviceName: 'BNS Phone',
          caregiverDevice: false,
          guidedMode: true,
          fullCareMode: true,
          careLevel: 4,
          shareName: 'Ben',
          careLockHash: 'salt:person-key');
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: person);
      final after = await IsarService.getSettings();
      expect(after.caregiverDevice, isTrue);
      expect(after.guidedMode, isFalse);
      expect(after.shareName, 'עוזרת');
      expect(after.careLockHash, 'salt:care-key');
    });

    test('the person never adopts a helper\'s hat — the cage stays shut',
        () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: false,
          guidedMode: true,
          fullCareMode: true,
          careLevel: 4,
          shareName: 'Ben',
          careLockHash: 'salt:person-key'));
      final helper = (await IsarService.getSettings()).copyWith(
          deviceId: 'care-1',
          deviceName: 'BNS Care',
          caregiverDevice: true,
          guidedMode: false,
          fullCareMode: false,
          careLevel: 1,
          shareName: 'עוזרת',
          careLockHash: '');
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: helper);
      final after = await IsarService.getSettings();
      expect(after.guidedMode, isTrue,
          reason: 'a Care pull must not open the level-4 cage');
      expect(after.fullCareMode, isTrue);
      expect(after.careLevel, 4);
      expect(after.shareName, 'Ben');
      expect(after.careLockHash, 'salt:person-key');
      expect(after.caregiverDevice, isFalse);
    });

    test('the person\'s own two devices still converge', () async {
      final s = await IsarService.getSettings();
      final otherOwnDevice = s.copyWith(
          deviceId: 'phone-1',
          deviceName: 'BNS Phone',
          caregiverDevice: false,
          fullCareMode: true,
          careLevel: 3,
          shareName: 'Ben');
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: otherOwnDevice);
      final after = await IsarService.getSettings();
      expect(after.fullCareMode, isTrue,
          reason: 'a level chosen together reaches the person\'s other device');
      expect(after.careLevel, 3);
      expect(after.shareName, 'Ben');
    });
  });

  group('person-day 15:00 survives save, reload, and a Care copy', () {
    test('15 lives through updateSettings and a pretend restart', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(
          s.copyWith(dayStartHour: 15, dayRolloverHour: 5));
      await IsarService.debugResetForTest();
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15);
      expect(after.dayRolloverHour, 5);
    });

    test('a helper full snapshot with 0 cannot midnight the person', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: false, dayStartHour: 15, dayRolloverHour: 5));
      final helper = (await IsarService.getSettings()).copyWith(
          deviceId: 'care-1',
          deviceName: 'BNS Care',
          caregiverDevice: true,
          dayStartHour: 0,
          dayRolloverHour: 0);
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: helper);
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15,
          reason: 'Care receive-first / a helper copy must not eat 15:00');
      expect(after.dayRolloverHour, 5);
      expect(after.caregiverDevice, isFalse);
    });

    test('Care learns 15 from the person\'s own store', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(s.copyWith(
          caregiverDevice: true, dayStartHour: 0, dayRolloverHour: 0));
      final person = (await IsarService.getSettings()).copyWith(
          deviceId: 'person-1',
          deviceName: 'BNS Phone',
          caregiverDevice: false,
          dayStartHour: 15,
          dayRolloverHour: 5);
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: person);
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15,
          reason: 'the inspector\'s clock is the person\'s day');
      expect(after.dayRolloverHour, 5);
      expect(after.caregiverDevice, isTrue);
    });

    test('an empty care-window stub cannot midnight a set 15', () async {
      final s = await IsarService.getSettings();
      await IsarService.updateSettings(
          s.copyWith(dayStartHour: 15, dayRolloverHour: 5));
      const stub = AppSettings(); // empty deviceId, hours 0
      expect(stub.deviceId, isEmpty);
      await IsarService.mergeData(
          routines: [],
          events: [],
          captures: [],
          logs: [],
          incomingSettings: stub);
      final after = await IsarService.getSettings();
      expect(after.dayStartHour, 15);
      expect(after.dayRolloverHour, 5);
    });
  });
}
