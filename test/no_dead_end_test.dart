/// THE NO-DEAD-END GUARANTEE — every room keeps a door at every width,
/// and back never exits from an inner room.
///
/// Owner, 2026-08-18: "went to routines as caregiver and couldn't get
/// out without increasing window size... pushed back on android, it
/// exit the program." Two laws, held here:
///
///  1. A bar that steps aside for the sidebar may do so only when the
///     sidebar is actually there (width ≥ 820) — a narrow desktop
///     window keeps the bar and its ☰/back.
///  2. System back from a routed room that is not home goes HOME;
///     only home hands the gesture to the system.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/bns_desktop_shell.dart';

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
    root = await Directory.systemTemp.createTemp('bns_no_dead_end_');
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

  group('the bar steps aside only when the sidebar is there', () {
    // The bar asks the WINDOW its width (preferredSize has no context),
    // so the tests drive the test view's physical size directly.
    Future<void> pumpAtWidth(WidgetTester tester, double logicalW) async {
      tester.view.physicalSize =
          Size(logicalW * tester.view.devicePixelRatio, 2100);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          appBar: BnsAppBar(title: 'ניהול שגרות', hideOnDesktopWide: true),
          body: SizedBox(),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('narrow desktop window keeps the bar', (tester) async {
      await pumpAtWidth(tester, 800);
      expect(find.text('ניהול שגרות'), findsOneWidget,
          reason: 'no sidebar below 820 — the bar must hold the doors');
    });

    testWidgets('wide desktop window lets the sidebar own the chrome',
        (tester) async {
      await pumpAtWidth(tester, 1200);
      expect(find.text('ניהול שגרות'), findsNothing,
          reason: 'at wide the sidebar shell holds the doors instead');
    });
  });

  group('back never exits from an inner room', () {
    GoRouter router() => GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (c, s) => BnsDesktopShell(
                  currentPath: s.uri.toString(),
                  child: const Scaffold(body: Text('home-room'))),
            ),
            GoRoute(
              path: '/routines',
              builder: (c, s) => BnsDesktopShell(
                  currentPath: s.uri.toString(),
                  child: const Scaffold(body: Text('routines-room'))),
            ),
          ],
        );

    testWidgets('system back from /routines lands home, app stays open',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final r = router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();

      r.go('/routines');
      await tester.pumpAndSettle();
      expect(find.text('routines-room'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isTrue,
          reason: 'the gesture is consumed — the app must not exit');
      expect(find.text('home-room'), findsOneWidget,
          reason: 'back from an inner room goes home, not out');
    });

    testWidgets('back at home hands the gesture to the system',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final r = router();
      await tester.pumpWidget(MaterialApp.router(routerConfig: r));
      await tester.pumpAndSettle();
      expect(find.text('home-room'), findsOneWidget);

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(handled, isFalse,
          reason: 'only home itself may let the app close');
    });
  });
}
