/// THE PERSON ANSWERS — and a caregiver device cannot answer for them
/// (owner, 2026-08-16: "the caregiver cannot set done because it's the
/// user's helper"). The inspector builds the day and watches it; done,
/// skip, steps and take-backs are born only on the person's own device
/// and arrive at the helper's by sync.
///
/// These tests hold the store to that: on `caregiverDevice`, every
/// answer-writing door is a wall — and a log that arrived by sync cannot
/// be erased there either. The reminder planner already refuses to buzz
/// on a helper's device; that stays proven here too, fingerprint included,
/// so flipping a device to caregiver really cancels what was scheduled.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/core/reminder_plan.dart';
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

  Routine routine(String id) => Routine(
        id: id,
        title: 'לקחת תרופות',
        recurrenceType: RecurrenceType.daily,
        time: '08:00',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  CalendarEvent plan(String id, String date) => CalendarEvent(
        id: id,
        title: 'רופא שיניים',
        date: date,
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 1),
      );

  Future<void> beCaregiver(bool it) async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(caregiverDevice: it));
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bns_caregiver_test_');
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

  test('a caregiver device cannot write done, skip, steps or an answer',
      () async {
    await IsarService.addRoutine(routine('r1'));
    await IsarService.addEvent(plan('e1', '2026-08-16'));
    await beCaregiver(true);

    await IsarService.logCompletion(
        routineId: 'r1', date: '2026-08-16', status: CompletionStatus.done);
    expect(await IsarService.getLogsForDate('2026-08-16'), isEmpty,
        reason: 'the ✓ belongs to the person');

    await IsarService.logCompletion(
        routineId: 'r1',
        date: '2026-08-16',
        status: CompletionStatus.skipped,
        reason: 'the helper typed this');
    expect(await IsarService.getLogsForDate('2026-08-16'), isEmpty,
        reason: 'the why belongs to the person too');

    final steps = await IsarService.advanceStep('r1', '2026-08-16', 3);
    expect(steps, 0, reason: 'steps are the person\'s walking');
    expect(await IsarService.getStepProgress('r1', '2026-08-16'), 0);

    await IsarService.answerEvent('e1', 'done');
    final events = await IsarService.getEventsForDate('2026-08-16');
    expect(events.single.answer, isNull,
        reason: 'a plan\'s answer is the person\'s answer');
  });

  test('an answer that arrived by sync cannot be taken back by the helper',
      () async {
    await IsarService.addRoutine(routine('r1'));
    // On the person's own device the ✓ writes fine…
    await IsarService.logCompletion(
        routineId: 'r1', date: '2026-08-16', status: CompletionStatus.done);
    expect(await IsarService.getLogsForDate('2026-08-16'), hasLength(1));

    // …and once this store plays the caregiver role, the ✓ is untouchable.
    await beCaregiver(true);
    await IsarService.removeCompletion(routineId: 'r1', date: '2026-08-16');
    expect(await IsarService.getLogsForDate('2026-08-16'), hasLength(1),
        reason: 'the answer belongs to whoever gave it');
  });

  test('the same doors are open on the person\'s own device', () async {
    await IsarService.addRoutine(routine('r1'));
    await IsarService.addEvent(plan('e1', '2026-08-16'));

    await IsarService.logCompletion(
        routineId: 'r1', date: '2026-08-16', status: CompletionStatus.done);
    expect(await IsarService.getLogsForDate('2026-08-16'), hasLength(1));

    await IsarService.answerEvent('e1', 'done');
    expect((await IsarService.getEventsForDate('2026-08-16')).single.answer,
        'done');

    await IsarService.removeCompletion(routineId: 'r1', date: '2026-08-16');
    expect(await IsarService.getLogsForDate('2026-08-16'), isEmpty,
        reason: 'taking a ✓ back stays the person\'s right');
  });

  test('no reminder ever rings in the helper\'s pocket — and the flip '
      'really cancels', () {
    final routines = [routine('r1')];
    final now = DateTime(2026, 8, 16, 6, 0);
    const person = AppSettings();
    final helper = person.copyWith(caregiverDevice: true);

    expect(
        planReminders(
            routines: routines, events: const [], settings: person, now: now),
        isNotEmpty,
        reason: 'sanity: this routine does ring on the person\'s device');
    expect(
        planReminders(
            routines: routines, events: const [], settings: helper, now: now),
        isEmpty);
    expect(
        reminderFingerprint(
            routines: routines, events: const [], settings: person, now: now),
        isNot(reminderFingerprint(
            routines: routines, events: const [], settings: helper, now: now)),
        reason: 'a changed fingerprint is what sweeps the stale ones away');
  });
}
