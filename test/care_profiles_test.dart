/// CARE PROFILES — one seat, many people, zero misfires (the tests).
///
/// docs/care-profiles.md is the law; these hold it: a profile is its own
/// complete store; the sitting swaps the ACTIVE store wholesale while
/// the seat's hat stays on; migration moves a pre-profile person behind
/// the first named door by themselves; trust is found across every door
/// (so silence can replace the severing word); an inbox merges the
/// moment a door opens.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/care_profiles.dart';
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
    root = await Directory.systemTemp.createTemp('bns_care_profiles_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    final home = Directory(p.join(root.path, 'home'))
      ..createSync(recursive: true);
    await IsarService.debugResetForTest();
    BnsHome.debugClearForcedForTest();
    await BnsHome.setDir(home);
    // Every test runs on a helper's seat.
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(
        s.copyWith(caregiverDevice: true, shareName: 'מלווה'));
  });

  tearDown(() async {
    await IsarService.debugResetForTest();
    BnsHome.debugClearForcedForTest();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Routine routine(String id) => Routine(
        id: id,
        title: 'לקחת תרופות',
        recurrenceType: RecurrenceType.daily,
        time: '08:00',
        createdAt: DateTime(2026, 8, 17),
        updatedAt: DateTime(2026, 8, 17),
      );

  test('a new door: own store, seat\'s hat on, listed in the index',
      () async {
    final prof = await CareProfiles.create('דנה');
    final dir = await CareProfiles.profileDir(prof.id);
    final store =
        jsonDecode(await File('${dir.path}/bns_data.json').readAsString());
    expect(store['settings']['caregiverDevice'], isTrue,
        reason: 'every guard keeps answering "I am the helper" in any seat');
    expect(store['settings']['guidedMode'], isFalse);
    expect((await CareProfiles.list()).map((e) => e.name), ['דנה']);
  });

  test('the sitting swaps the ACTIVE store wholesale, and stands back up',
      () async {
    final dana = await CareProfiles.create('דנה');
    await CareProfiles.enter(dana);
    await IsarService.addRoutine(routine('r-dana'));
    expect((await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-dana'));
    expect(await CareProfiles.sittingId(), dana.id);

    await CareProfiles.standUp();
    final atRoot = await IsarService.getAllRoutines();
    expect(atRoot.any((r) => r.id == 'r-dana'), isFalse,
        reason: 'דנה\'s day lives behind דנה\'s door only');
    expect(await CareProfiles.sittingId(), isNull);
  });

  test('the remembered sitting reopens at launch', () async {
    final dana = await CareProfiles.create('דנה');
    await CareProfiles.enter(dana);
    await IsarService.addRoutine(routine('r-dana'));
    // "Relaunch": cache dropped, sitting cleared in memory.
    await IsarService.debugResetForTest();
    BnsHome.sitIn(null);
    final resumed = await CareProfiles.resumeSitting();
    expect(resumed?.id, dana.id);
    expect((await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-dana'));
  });

  test('migration: the one merged person becomes the first named door',
      () async {
    // A pre-profile Care store: person data + their trusted device.
    await IsarService.addRoutine(routine('r-ben'));
    await IsarService.saveTrustedDevice(TrustedDevice(
      id: 'phone-ben',
      name: 'Ben',
      lastAddress: '192.168.31.5',
      lastSyncedAt: DateTime(2026, 8, 16),
      sharedSecret: 'c2VjcmV0',
    ));

    final prof = await CareProfiles.migrateLegacyIfNeeded();
    expect(prof, isNotNull);
    expect(prof!.name, 'Ben', reason: 'named from the person, not a number');

    // The root store is the seat's alone now.
    expect(await IsarService.getAllRoutines(), isEmpty);
    expect(await IsarService.getTrustedDevices(), isEmpty);
    expect((await IsarService.getSettings()).caregiverDevice, isTrue);

    // The person's whole day lives behind their door.
    await CareProfiles.enter(prof);
    expect((await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-ben'));
    expect((await IsarService.getTrustedDevice('phone-ben'))?.name, 'Ben');
    await CareProfiles.standUp();

    // Silk means once: a second launch changes nothing.
    expect(await CareProfiles.migrateLegacyIfNeeded(), isNull);
  });

  test('trustAnywhere finds a person behind a CLOSED door', () async {
    final dana = await CareProfiles.create('דנה');
    await CareProfiles.enter(dana);
    await IsarService.saveTrustedDevice(TrustedDevice(
      id: 'phone-dana',
      name: 'דנה',
      lastAddress: '',
      lastSyncedAt: DateTime(2026, 8, 17),
      sharedSecret: 'c2VjcmV0',
    ));
    await CareProfiles.standUp();

    final claim = await CareProfiles.trustAnywhere('phone-dana');
    expect(claim, isNotNull,
        reason: 'unknown to the sitting store is not unpaired — '
            'silence, never the severing word');
    expect(claim!.profileId, dana.id);
    expect(await CareProfiles.trustAnywhere('stranger'), isNull,
        reason: 'a true stranger is still a stranger');
  });

  test('an inbox merges the moment the door opens', () async {
    // Build a .bns behind door Q, leave it in P's inbox, open P.
    final q = await CareProfiles.create('קובי');
    await CareProfiles.enter(q);
    await IsarService.addRoutine(routine('r-inbox'));
    final bns = await BnsExporter.exportFullSnapshot();
    final bytes = await bns.readAsBytes();
    await CareProfiles.standUp();

    final pDoor = await CareProfiles.create('פנינה');
    await CareProfiles.keepInInbox(pDoor.id, bytes);
    await CareProfiles.enter(pDoor);
    expect((await IsarService.getAllRoutines()).map((r) => r.id),
        contains('r-inbox'),
        reason: 'receive-first: what arrived while the door was closed '
            'is in before anything is built on top');
    final inbox = await CareProfiles.inboxDir(pDoor.id);
    final left = await inbox.exists() ? await inbox.list().toList() : [];
    expect(left, isEmpty, reason: 'a merged push does not linger');
  });
}
