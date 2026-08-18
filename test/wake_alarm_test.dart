/// THE WAKE — a reason carried by a ring (owner as user, 2026-08-18:
/// "I don't get the notifications, I need an alarm clock... many days
/// have nothing to wake up for and I do have").
///
/// Held here:
///  - the wake survives the store (settings round-trip, '' = off);
///  - the ring's words are the day's opening, in owl order, never empty;
///  - the Tomorrow room offers the wake to the person — and never to a
///    Care seat (the seat's wake belongs on the person's nightstand).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/wake_words.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/calendar/tomorrow_screen.dart';
import 'package:bns/features/wake/wake_screen.dart';
import 'package:bns/ui/widgets/bns_menu_screen.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the wake survives the store', () {
    test('round-trip keeps time and note; default is off', () {
      const s = AppSettings();
      expect(s.wakeAlarmTime, '');
      expect(s.wakeAlarmNote, '');

      final kept = AppSettings.fromJson(s
          .copyWith(wakeAlarmTime: '07:30', wakeAlarmNote: 'קפה עם אבא')
          .toJson());
      expect(kept.wakeAlarmTime, '07:30');
      expect(kept.wakeAlarmNote, 'קפה עם אבא');

      // A file from before the wake existed simply has no wake.
      final old = AppSettings.fromJson(const AppSettings().toJson()
        ..remove('wakeAlarmTime')
        ..remove('wakeAlarmNote'));
      expect(old.wakeAlarmTime, '');
    });
  });

  group('the ring carries the day', () {
    final now = DateTime(2026, 8, 19, 7, 30);

    Routine r(String title, String? time) => Routine(
        id: title,
        title: title,
        recurrenceType: RecurrenceType.daily,
        time: time,
        createdAt: now,
        updatedAt: now);

    CalendarEvent e(String title, String? time) => CalendarEvent(
        id: title,
        title: title,
        date: '2026-08-19',
        time: time,
        createdAt: now,
        updatedAt: now);

    test('owl order, three at most, timeless closes the line', () {
      final body = wakeBodyFor(
        routines: [r('תרופות', '08:00'), r('ערב', '23:00')],
        events: [e('בדיקת דם', '07:00'), e('לנוח', null)],
        day: DateTime(2026, 8, 19),
        rolloverHour: 4,
        t: (en, he) => he,
      );
      expect(body, 'בדיקת דם 07:00 · תרופות 08:00 · ערב 23:00',
          reason: 'first three in the person\'s order; timeless waits');
    });

    test('a night thing (02:00, border 04:00) never leads the morning', () {
      final body = wakeBodyFor(
        routines: [r('כדורי לילה', '02:00'), r('בוקר', '08:00')],
        events: const [],
        day: DateTime(2026, 8, 19),
        rolloverHour: 4,
        t: (en, he) => he,
      );
      expect(body.startsWith('בוקר 08:00'), isTrue,
          reason: '02:00 belongs to the END of the person-day');
    });

    test('an empty day still gives a reason', () {
      final body = wakeBodyFor(
        routines: const [],
        events: const [],
        day: DateTime(2026, 8, 19),
        rolloverHour: 0,
        t: (en, he) => he,
      );
      expect(body, 'היום שלך מחכה לך.');
    });
  });

  group('the tomorrow room offers the wake', () {
    Future<void> seed(WidgetTester tester, {bool caregiver = false}) async {
      await tester.runAsync(() async {
        final root = Directory.systemTemp.createTempSync('bns_wake_');
        PathProviderPlatform.instance = _FakePathProvider(root.path);
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        await IsarService.debugResetForTest();
        BnsHome.debugClearForcedForTest();
        await BnsHome.setDir(home);
        final s = await IsarService.getSettings();
        await IsarService.updateSettings(
            s.copyWith(caregiverDevice: caregiver));
        await IsarService.getSettings();
      });
      addTearDown(() async {
        await tester.runAsync(() => IsarService.debugResetForTest());
      });
    }

    Future<void> pumpRoom(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: TomorrowScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('the person sets the wake through the fusion sheet',
        (tester) async {
      L.lang = 'he';
      await seed(tester);
      await pumpRoom(tester);

      expect(find.text('לקבוע שעת השכמה'), findsOneWidget);
      await tester.tap(find.text('לקבוע שעת השכמה'));
      await tester.pumpAndSettle();

      // The sheet opens on 07:30 — confirm wears the time it will set.
      await tester.tap(find.textContaining('לקבוע — 07:30'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        final s = await IsarService.getSettings();
        expect(s.wakeAlarmTime, '07:30');
      });
      expect(find.textContaining('השכמה — 07:30'), findsOneWidget);
    });

    testWidgets('a Care seat has no wake doors — it rings on THEIR '
        'nightstand, not the helper\'s', (tester) async {
      L.lang = 'he';
      await seed(tester, caregiver: true);
      await pumpRoom(tester);

      expect(find.text('השכמה'), findsNothing);
      expect(find.text('לקבוע שעת השכמה'), findsNothing);
    });

    testWidgets('the wake room: the person gets the controls, a pinned way '
        'back, and the same one implementation', (tester) async {
      L.lang = 'he';
      await seed(tester);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: WakeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('לקבוע שעת השכמה'), findsOneWidget);
      expect(find.text('חזרה'), findsOneWidget);
    });

    testWidgets('the wake room on a Care seat says where the wake lives '
        'instead of offering doors', (tester) async {
      L.lang = 'he';
      await seed(tester, caregiver: true);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: WakeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('לקבוע שעת השכמה'), findsNothing);
      expect(find.textContaining('ההשכמה גרה אצלם'), findsOneWidget,
          reason: 'a quiet word beats a silently missing door');
    });

    testWidgets('the menu map names the alarm-clock door', (tester) async {
      L.lang = 'he';
      await seed(tester);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: BnsMenuScreen()));
      await tester.pumpAndSettle();

      expect(find.text('שעון מעורר'), findsOneWidget);
      expect(find.text('מה נשאר היום — וצלצול אמיתי לכל משימה'),
          findsOneWidget);
    });

    testWidgets('the alarm page shows what is left today, in order',
        (tester) async {
      L.lang = 'he';
      await seed(tester);
      await tester.runAsync(() async {
        final now = DateTime.now();
        await IsarService.addRoutine(Routine(
          id: 'r-evening-meds',
          title: 'תרופות ערב',
          recurrenceType: RecurrenceType.daily,
          time: '20:00',
          createdAt: now,
          updatedAt: now,
        ));
      });
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: WakeScreen()));
      await tester.pumpAndSettle();

      expect(find.text('מה נשאר היום'), findsOneWidget);
      expect(find.text('תרופות ערב'), findsOneWidget,
          reason: 'an unanswered mission is offered to become a ring');
      expect(find.text('20:00'), findsOneWidget);
    });
  });
}
