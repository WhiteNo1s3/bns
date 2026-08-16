/// THE RETURN DOOR — a pushed day always walks back out, in words.
///
/// Owner, 2026-08-17: "I cannot return when I am at a day in the future,
/// just one screen... I would like to correct it with a return button."
/// The day view is pushed over the whole shell; an unlabeled arrow among
/// icons is not a door for a tired person. These tests hold the room to:
///
///  - a worded «חזרה» pinned under the day, phone width and wide desktop
///    alike, that actually LEAVES back to the room the day was opened from;
///  - done as a QUIET ✓ (owner law 2026-07-08; cross-tree 2026-08-17):
///    marking a routine asks no second question.
///
/// First widget tests in the suite. The store does real file I/O, and a
/// widget test lives in a fake-async zone — so every store touch happens
/// inside [WidgetTester.runAsync], and the cache is primed BEFORE the
/// first pump so the day view's own loads resolve as plain microtasks.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/calendar/day_view.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fresh isolated store, built in the REAL async zone; leaves the
  /// settings cache primed so widget-side loads are microtask-only.
  Future<Directory> freshStore(WidgetTester tester) async {
    late Directory root;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('bns_return_door_');
      PathProviderPlatform.instance = _FakePathProvider(root.path);
      final home = Directory(p.join(root.path, 'home'))
        ..createSync(recursive: true);
      await IsarService.debugResetForTest();
      await BnsHome.setDir(home);
      await IsarService.getSettings(); // prime the cache
    });
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    return root;
  }

  /// Flush pending writes and drop the cache — in the real zone, so the
  /// fake-async test zone never waits on a disk.
  Future<void> closeStore(WidgetTester tester) =>
      tester.runAsync(() => IsarService.debugResetForTest());

  /// A tiny "shell": one screen that PUSHES the day view over itself,
  /// exactly like the calendar and the tomorrow door do.
  Future<void> pumpPushedDay(
      WidgetTester tester, DateTime date, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => DayView(date: date))),
              child: const Text('the-map'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('the-map'));
    await tester.pumpAndSettle();
  }

  testWidgets('a future day at phone width has a worded way back',
      (tester) async {
    await freshStore(tester);
    final now = DateTime.now();
    await tester.runAsync(() => IsarService.addRoutine(Routine(
          id: 'r-daily',
          title: 'לקחת תרופות',
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          createdAt: now,
          updatedAt: now,
        )));
    final tomorrow = now.add(const Duration(days: 1));
    await pumpPushedDay(tester, tomorrow, const Size(390, 844));

    expect(find.text('חזרה'), findsOneWidget,
        reason: 'the door wears its name — not an arrow glyph');

    // Tomorrow is look-only (level-1 note, 2026-08-17): the routine is
    // named, but wears no box and no pencil — nothing begs a tap.
    expect(find.text('לקחת תרופות'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsNothing);
    expect(find.byIcon(Icons.edit_note), findsNothing);

    await tester.tap(find.text('חזרה'));
    await tester.pumpAndSettle();
    expect(find.text('the-map'), findsOneWidget,
        reason: 'the door actually leaves, back to the map');
    await closeStore(tester);
  });

  testWidgets('the same worded door exists on a wide desktop window',
      (tester) async {
    await freshStore(tester);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await pumpPushedDay(tester, tomorrow, const Size(1440, 900));

    expect(find.text('חזרה'), findsOneWidget);
    await tester.tap(find.text('חזרה'));
    await tester.pumpAndSettle();
    expect(find.text('the-map'), findsOneWidget);
    await closeStore(tester);
  });

  testWidgets('marking done is a quiet ✓ — no second question',
      (tester) async {
    await freshStore(tester);
    final now = DateTime.now();
    await tester.runAsync(() => IsarService.addRoutine(Routine(
          id: 'r-meds',
          title: 'לקחת תרופות',
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          createdAt: now,
          updatedAt: now,
        )));

    await pumpPushedDay(tester, now, const Size(390, 844));

    await tester.tap(find.text('לקחת תרופות'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing,
        reason: 'done is a quiet ✓, never a follow-up question');
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final logs = await tester
        .runAsync(() => IsarService.getLogsForDate(todayStr));
    expect(
        logs!.any((l) =>
            l.routineId == 'r-meds' && l.status == CompletionStatus.done),
        isTrue,
        reason: 'the tap itself wrote the answer');

    // Taking a kept answer BACK still asks — one guard for one answer.
    await tester.tap(find.text('לקחת תרופות'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await closeStore(tester);
  });
}
