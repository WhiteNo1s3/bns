/// THE THREE DAYS LAW + THE TOMORROW ROOM (owner as user, 2026-08-18:
/// "I can go to the days before and insert useless information... the
/// plan for tomorrow should have its own screen showing the next day's
/// plan including addons... instead of to show all hours the day have
/// including the past").
///
/// Held here:
///  - the PAST is written: no plan door on days before, a quiet line
///    says why; the person's clock decides what "before" means;
///  - the FUTURE takes plans (planning ahead is the point) — only the ✓
///    waits for its day;
///  - TOMORROW is one entity in its own room: routines wearing their
///    steps, add-ons at their hour, woven in the person's day order;
///  - the fusion sheet's floor: gone hours are not on the rail.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/calendar/day_view.dart';
import 'package:bns/features/calendar/tomorrow_screen.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('owl: the past is written', () {
    test('yesterday is past, today and tomorrow are not', () {
      final now = DateTime(2026, 8, 18, 12, 0);
      bool past(DateTime day) => alreadyWritten(
          day: day, now: now, rolloverHour: 0, startHour: 0);
      expect(past(DateTime(2026, 8, 17)), isTrue);
      expect(past(DateTime(2026, 8, 18)), isFalse);
      expect(past(DateTime(2026, 8, 19)), isFalse);
    });

    test('at 02:00 with border 04:00 yesterday\'s date is still THIS day',
        () {
      final now = DateTime(2026, 8, 18, 2, 0); // the night of Aug 17
      bool past(DateTime day) => alreadyWritten(
          day: day, now: now, rolloverHour: 4, startHour: 15);
      expect(past(DateTime(2026, 8, 17)), isFalse,
          reason: 'their Aug 17 is still going — not written yet');
      expect(past(DateTime(2026, 8, 16)), isTrue);
      // And the calendar's "today" has not come on their clock.
      expect(
          lookOnly(
              day: DateTime(2026, 8, 18),
              now: now,
              rolloverHour: 4,
              startHour: 15),
          isTrue);
    });
  });

  group('the fusion sheet holds its floor', () {
    testWidgets('gone hours are not on the rail, −15 cannot walk below',
        (tester) async {
      L.lang = 'he';
      TimeOfDay? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await showTimeFusionSheet(
                      context: context,
                      title: 'באיזו שעה?',
                      initial: const TimeOfDay(hour: 10, minute: 0),
                      minHour: 10);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('09:00'), findsNothing,
          reason: 'an hour that passed is simply not offered');
      expect(find.text('10:00'), findsWidgets);

      await tester.tap(find.textContaining('−15'));
      await tester.pump();
      expect(find.textContaining('לקבוע — 10:00'), findsOneWidget,
          reason: 'the floor holds — no step below the first open hour');

      await tester.tap(find.textContaining('לקבוע'));
      await tester.pumpAndSettle();
      expect(result, const TimeOfDay(hour: 10, minute: 0));
    });
  });

  group('the day view knows its three days', () {
    Future<Directory> freshStore(WidgetTester tester) async {
      late Directory root;
      await tester.runAsync(() async {
        root = Directory.systemTemp.createTempSync('bns_tomorrow_');
        PathProviderPlatform.instance = _FakePathProvider(root.path);
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        await IsarService.debugResetForTest();
        BnsHome.debugClearForcedForTest();
        await BnsHome.setDir(home);
        await IsarService.getSettings(); // prime the cache
      });
      addTearDown(() async {
        await tester.runAsync(() => IsarService.debugResetForTest());
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      });
      return root;
    }

    Future<void> pumpDay(WidgetTester tester, DateTime date) async {
      await tester.binding.setSurfaceSize(const Size(800, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: DayView(date: date)));
      await tester.pumpAndSettle();
    }

    testWidgets('a day already written offers no plan door', (tester) async {
      L.lang = 'he';
      await freshStore(tester);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await pumpDay(tester, yesterday);

      expect(find.text('להוסיף אירוע ליום הזה'), findsNothing,
          reason: 'the past takes no plans');
      expect(find.text('יום שעבר נשאר כמו שהיה.'), findsOneWidget,
          reason: 'a missing door without a word feels broken');
    });

    testWidgets('a coming day still takes plans — only the ✓ waits',
        (tester) async {
      L.lang = 'he';
      await freshStore(tester);
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await pumpDay(tester, tomorrow);

      expect(find.text('להוסיף אירוע ליום הזה'), findsOneWidget,
          reason: 'planning ahead is the point of a calendar');
    });
  });

  group('the tomorrow room', () {
    Future<void> seed(WidgetTester tester,
        {bool guided = false, int rollover = 0}) async {
      await tester.runAsync(() async {
        final root = Directory.systemTemp.createTempSync('bns_tmrw_room_');
        PathProviderPlatform.instance = _FakePathProvider(root.path);
        final home = Directory(p.join(root.path, 'home'))
          ..createSync(recursive: true);
        await IsarService.debugResetForTest();
        BnsHome.debugClearForcedForTest();
        await BnsHome.setDir(home);

        final s = await IsarService.getSettings();
        await IsarService.updateSettings(s.copyWith(
            guidedMode: guided, dayRolloverHour: rollover));

        final now = DateTime.now();
        final tomorrow = logicalDateOf(now, rollover)
            .add(const Duration(days: 1));
        final tomorrowKey = DateFormat('yyyy-MM-dd').format(tomorrow);

        await IsarService.addRoutine(Routine(
          id: 'r-meds',
          title: 'תרופות בוקר',
          recurrenceType: RecurrenceType.daily,
          time: '08:00',
          steps: const [
            RoutineStep(title: 'לקחת כדורים', note: 'עם מים'),
            RoutineStep(title: 'לבדוק לחץ דם'),
          ],
          createdAt: now,
          updatedAt: now,
        ));
        await IsarService.addEvent(CalendarEvent(
          id: 'e-blood',
          title: 'בדיקת דם',
          date: tomorrowKey,
          time: '07:00',
          createdAt: now,
          updatedAt: now,
        ));
        await IsarService.addEvent(CalendarEvent(
          id: 'e-rest',
          title: 'לנוח בצהריים',
          date: tomorrowKey,
          time: null,
          createdAt: now,
          updatedAt: now,
        ));
        await IsarService.getSettings(); // cache stays primed
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

    testWidgets(
        'one woven plan: routines wear their steps, add-ons at their hour, '
        'timeless rows close the list', (tester) async {
      L.lang = 'he';
      await seed(tester);
      await pumpRoom(tester);

      // The plan sticks to its entity — the steps are ON it.
      expect(find.text('תרופות בוקר'), findsOneWidget);
      expect(find.text('· לקחת כדורים — עם מים'), findsOneWidget);
      expect(find.text('· לבדוק לחץ דם'), findsOneWidget);
      expect(find.text('בדיקת דם'), findsOneWidget);
      expect(find.text('לנוח בצהריים'), findsOneWidget);

      // Woven in day order: 07:00 add-on, 08:00 routine, then timeless.
      final yBlood = tester.getTopLeft(find.text('בדיקת דם')).dy;
      final yMeds = tester.getTopLeft(find.text('תרופות בוקר')).dy;
      final yRest = tester.getTopLeft(find.text('לנוח בצהריים')).dy;
      expect(yBlood, lessThan(yMeds));
      expect(yMeds, lessThan(yRest));

      // The room builds: an add door and a pinned way back, no ✓ anywhere.
      expect(find.text('להוסיף תוכנית למחר'), findsOneWidget);
      expect(find.text('חזרה'), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsNothing);
    });

    testWidgets('guided: the room is a window, not a workbench',
        (tester) async {
      L.lang = 'he';
      await seed(tester, guided: true);
      await pumpRoom(tester);

      expect(find.text('להוסיף תוכנית למחר'), findsNothing,
          reason: 'level 4: the day is built by the inspector');
      expect(find.text('להסיר'), findsNothing);
      expect(find.text('תרופות בוקר'), findsOneWidget,
          reason: 'looking at tomorrow stays open to everyone');
    });
  });
}
