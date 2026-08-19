/// DON'T INVENT A PLAN (Eagered: the calendar's + auto-made a nameless
/// «פגישה חדשה / הערה» at 03:07 — "Ask for a name or don't create it").
///
/// Held here:
///  - the + path (DayView startWithAdd) opens the ask and creates NOTHING
///    by itself — leaving through ביטול leaves the store empty;
///  - «הוספה» sleeps while the name is empty — silence cannot name a plan;
///  - a typed name creates exactly that plan, nothing generic.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/calendar/day_view.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => L.lang = 'he');

  // Real IO lives under runAsync; the settings read primes the cache so
  // the screen's loads settle inside the fake-async pump (the
  // tomorrow-room recipe).
  Future<void> freshStore(WidgetTester tester) async {
    late Directory root;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('bns_named_plan_');
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
      BnsHome.debugClearForcedForTest();
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
  }

  Future<void> pumpDayView(WidgetTester tester,
      {bool startWithAdd = false}) async {
    await freshStore(tester);
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: DayView(date: DateTime.now(), startWithAdd: startWithAdd),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the + opens the ask; ביטול leaves the store empty',
      (tester) async {
    await pumpDayView(tester, startWithAdd: true);

    expect(find.text('הוספת אירוע ליום הזה'), findsOneWidget,
        reason: 'startWithAdd must land in the ONE add ask');
    expect(find.text('מה קורה?'), findsOneWidget);

    await tester.tap(find.text('ביטול'));
    await tester.pumpAndSettle();

    final events =
        await tester.runAsync(() => IsarService.getAllEvents());
    expect(events, isEmpty,
        reason: 'walking away from the ask must invent nothing');
  });

  testWidgets('הוספה sleeps while the name is empty', (tester) async {
    await pumpDayView(tester, startWithAdd: true);

    final addDoor = find.widgetWithText(FilledButton, 'הוספה');
    expect(addDoor, findsOneWidget);
    expect(tester.widget<FilledButton>(addDoor).onPressed, isNull,
        reason: 'silence cannot name a plan');

    await tester.tap(addDoor, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => IsarService.getAllEvents()), isEmpty);
    expect(find.text('הוספת אירוע ליום הזה'), findsOneWidget,
        reason: 'the ask stays up — nothing was answered');
  });

  testWidgets('a typed name creates exactly that plan', (tester) async {
    await pumpDayView(tester, startWithAdd: true);

    await tester.enterText(
        find.byType(TextField).first, 'רופא שיניים');
    await tester.pumpAndSettle();

    final addDoor = find.widgetWithText(FilledButton, 'הוספה');
    expect(tester.widget<FilledButton>(addDoor).onPressed, isNotNull,
        reason: 'a name wakes the door');
    await tester.tap(addDoor);
    await tester.pumpAndSettle();
    // The save's file write finishes on the real loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final events =
        (await tester.runAsync(() => IsarService.getAllEvents()))!;
    expect(events.length, 1);
    expect(events.single.title, 'רופא שיניים');
    expect(events.single.title, isNot(contains('פגישה חדשה')),
        reason: 'no invented generic names');
  });
}
