import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for LogicalKeyboardKey
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/ui/theme.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/providers/app_providers.dart';
import 'package:bns/ui/widgets/routine_tile.dart';
import 'package:bns/ui/widgets/quick_capture_bar.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/bns_desktop_shell.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/features/calendar/calendar_screen.dart';
import 'package:bns/features/sync/sync_screen.dart';
import 'package:bns/features/routines/routines_screen.dart';
import 'package:bns/features/memory/memories_screen.dart';
import 'package:home_widget/home_widget.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/services/file_handler.dart';
import 'package:confetti/confetti.dart';

void main(List<String> args) {
  // THE FIRST FRAME IS SACRED (black-screen fix, 2026-07-06): runApp runs
  // immediately — nothing is awaited before it. On Android 13+ the old code
  // awaited a notification PERMISSION DIALOG before the first frame, which
  // can block or fail silently → app opens to a plain black screen.
  // All startup chores now happen after the UI exists, each one guarded:
  // a failed chore degrades a feature, never the launch.
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // log, never die silently
  };
  runApp(const ProviderScope(child: BnsApp()));
  _startupChores(args);
}

Future<void> _startupChores(List<String> args) async {
  try {
    await NotificationsService.init();
    await NotificationsService.rescheduleAll();
  } catch (_) {
    // Reminders are a courtesy — the app runs fine without them today.
  }
  try {
    // Prune old historical data to keep files small (2-week default rolling).
    // Future planning (calendar) is preserved. Routines stay.
    await IsarService.pruneOldData();
  } catch (_) {}
  try {
    // Desktop: double-clicking an associated .bns file passes its path here.
    BnsFileHandler.checkDesktopArgs(args, null);
  } catch (_) {}
}

/// Wraps a page with the modern desktop shell when on PC (Windows/mac/Linux wide window).
/// Keeps exact same behavior on mobile / narrow windows.
/// Selected nav item is clearly marked in relaxing teal.
Widget _wrapForDesktop(BuildContext context, Widget child, String currentPath) {
  // Always wrap — the shell decides internally whether to show sidebar or not.
  return BnsDesktopShell(
    currentPath: currentPath,
    child: child,
  );
}

final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) =>
          _wrapForDesktop(context, const TodayScreen(), state.uri.toString()),
    ),
    GoRoute(
      path: '/calendar',
      builder: (context, state) => _wrapForDesktop(
          context, const CalendarScreen(), state.uri.toString()),
    ),
    GoRoute(
      path: '/capture',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final screen = QuickCaptureScreen(
          linkedRoutineId: extra['linkedRoutineId'] as String?,
          initialText: extra['initialText'] as String?,
          initialTags: (extra['tags'] as List?)?.cast<String>(),
          autoRecord: extra['autoRecord'] == true,
          doctorVisit: extra['doctorVisit'] == true,
        );
        return _wrapForDesktop(context, screen, state.uri.toString());
      },
    ),
    GoRoute(
      path: '/sync',
      builder: (context, state) =>
          _wrapForDesktop(context, const SyncScreen(), state.uri.toString()),
    ),
    GoRoute(
      path: '/routines',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _wrapForDesktop(
            context,
            RoutinesScreen(openNewOnStart: extra['openNew'] == true),
            state.uri.toString());
      },
    ),
    GoRoute(
      path: '/memories',
      builder: (context, state) => _wrapForDesktop(
          context, const MemoriesScreen(), state.uri.toString()),
    ),
  ],
);

class BnsApp extends ConsumerStatefulWidget {
  const BnsApp({super.key});

  @override
  ConsumerState<BnsApp> createState() => _BnsAppState();
}

class _BnsAppState extends ConsumerState<BnsApp> {
  late final AppLifecycleListener _lifecycle;
  int _lastImagedRevision = 0;
  bool _imaging = false;

  @override
  void initState() {
    super.initState();
    // Seamless imaging: the live store already persists every change
    // instantly; here we additionally refresh ONE ready-to-share .bns
    // (BNS_Latest_<device>.bns) whenever the app goes to background or is
    // asked to close — silent, skipped when nothing changed. The user never
    // saves anything; a current database file simply always exists.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          _sayGoodbye();
        } else if (state == AppLifecycleState.resumed) {
          // Session is live again — a crash from here on counts as unclean.
          IsarService.markSessionOpen();
        }
      },
      onExitRequested: () async {
        await _sayGoodbye();
        return AppExitResponse.exit;
      },
    );

    // Home-widget buttons: one tap on the home screen lands exactly where
    // the person needs to be (🎤 already recording, + Task in the form).
    if (Platform.isAndroid) {
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetLaunch);
      HomeWidget.widgetClicked.listen(_onWidgetLaunch);
      AndroidBnsWidget.updateWidget();
    }
  }

  void _onWidgetLaunch(Uri? uri) {
    if (uri == null) return;
    final where = uri.host.isNotEmpty ? uri.host : uri.path.replaceAll('/', '');
    switch (where) {
      case 'record':
        _router.go('/capture', extra: {'autoRecord': true});
      case 'add-memory':
        _router.go('/capture');
      case 'add-task':
        _router.go('/routines', extra: {'openNew': true});
      case 'calendar':
        _router.go('/calendar');
      default:
        _router.go('/');
    }
  }

  /// Graceful goodbye: flush writes, refresh the shareable image (unless the
  /// user disabled auto-imaging), and mark the session cleanly closed.
  Future<void> _sayGoodbye() async {
    await _imageIfChanged();
    try {
      await IsarService.markCleanExit();
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _imageIfChanged() async {
    if (_imaging || IsarService.revision == _lastImagedRevision) return;
    _imaging = true;
    final rev = IsarService.revision;
    try {
      await IsarService.flush();
      final settings = await IsarService.getSettings();
      if (settings.autoImageEnabled) {
        await BnsExporter.exportLatestSnapshot();
      }
      _lastImagedRevision = rev;
    } catch (_) {
      // Imaging is a bonus copy — the live store is already safe on disk.
    } finally {
      _imaging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fog =
        ref.watch(settingsProvider).asData?.value.fogReading == true;
    final app = MaterialApp.router(
      title: 'BNS',
      debugShowCheckedModeBanner: false,
      theme: BnsTheme.build(
        palette: RelaxingPalette.teal,
        mode: ThemeModeSetting.system,
      ),
      darkTheme: BnsTheme.build(
        palette: RelaxingPalette.teal,
        mode: ThemeModeSetting.dark,
      ),
      // Static app: even light/dark switches snap instead of morphing.
      themeAnimationDuration: Duration.zero,
      // Fog-first reading: bigger text globally when the person asks for it.
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(
                fog ? 1.22 : media.textScaler.scale(1.0)),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: _router,
    );

    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return app;
    }

    // Robust PC shortcuts, built LIVE from the user's saved keybinds
    // (Sync & PC screen: tick to enable, press to change — set & forget).
    // Unparseable combos are skipped quietly; a bad edit never breaks the app.
    final settings = ref.watch(settingsProvider).asData?.value;
    final binds = (settings?.keybinds.isNotEmpty ?? false)
        ? settings!.keybinds
        : Keybinds.defaults;
    final enabled = settings?.enabledKeybinds ?? Keybinds.defaultEnabled;

    final shortcuts = <ShortcutActivator, Intent>{};
    binds.forEach((id, combo) {
      if (enabled[id] == false) return;
      final activator = Keybinds.parse(combo);
      if (activator != null) shortcuts[activator] = _KeybindIntent(id);
    });

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          _KeybindIntent: CallbackAction<_KeybindIntent>(
            onInvoke: (intent) {
              _runKeybind(intent.id);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: app,
        ),
      ),
    );
  }
}

/// One intent for all configurable keybinds; the action id says what to do.
class _KeybindIntent extends Intent {
  final String id;
  const _KeybindIntent(this.id);
}

void _runKeybind(String id) {
  switch (id) {
    case 'open_today':
      _router.go('/');
      break;
    case 'open_routines':
      _router.go('/routines');
      break;
    case 'open_calendar':
      _router.go('/calendar');
      break;
    case 'open_memories':
      _router.go('/memories');
      break;
    case 'quick_capture':
      _router.go('/capture');
      break;
    case 'open_sync':
      _router.go('/sync');
      break;
    case 'focus_diary':
      _goTodayThen(() => TodayHooks.diary?.requestFocus());
      break;
    case 'focus_routines':
      _goTodayThen(() => TodayHooks.routines?.requestFocus());
      break;
    case 'save_diary':
      TodayHooks.saveDiary?.call();
      break;
    case 'mark_done':
      _goTodayThen(() => TodayHooks.markNextDone?.call());
      break;
  }
}

/// Navigate to Today, then run an action once the screen has had a moment
/// to build and register its hooks.
void _goTodayThen(VoidCallback action) {
  _router.go('/');
  Future.delayed(const Duration(milliseconds: 160), action);
}

/// Shown at most once per session: reassurance after a crash/kill.
bool _uncleanExitNoticeShown = false;

/// Live hooks the Today screen registers so global keybinds can reach
/// inside it (diary focus, list focus, save, mark-next-done).
class TodayHooks {
  static FocusNode? diary;
  static FocusNode? routines;
  static Future<void> Function()? saveDiary;
  static Future<void> Function()? markNextDone;
}

/// Today screen using real Riverpod + Isar data.
/// Positive, forgiving, linked to calendar and capture.
/// Confetti + skip-with-reason flow preserved.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late ConfettiController _confetti;
  final _diaryController =
      TextEditingController(); // for interactive diary entry
  final _diaryFocus =
      FocusNode(); // PC typing #1 — robust focus for keyboard users
  final _routinesFocus = FocusNode(); // keyboard navigation of today's steps
  int _kbSelected = -1; // which routine tile the keyboard has selected
  List<Routine> _todayRoutines =
      const []; // latest visible list for key handling
  String _userType = 'normal';
  bool _madActive = false; // "I am mad" mode — burns out on its own
  // Today's done-state, cached once per data change. The tiles read this
  // synchronously — no per-tile FutureBuilder re-querying the store on every
  // rebuild (that made each key press repaint/flicker the whole list).
  Set<String> _doneTodayIds = const {};
  Set<String> _skippedTodayIds = const {}; // "not today" — handled, no ✓
  Map<String, int> _stepProgress = const {}; // routineId → parts done today
  bool _nextFirstOrder = false; // false = morning→night (default)
  bool _guidedMode = false; // level 4: only the list, inspector builds
  String? _lastSyncLine; // cached "last synced" note (no per-frame queries)
  List<CalendarEvent> _specialOrders = const []; // out-of-ordinary on Today
  bool _welcomeBack = false; // calm rediscovery after a long gap
  bool _fogReading = false;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    // Register live hooks so global keybinds can reach into this screen.
    TodayHooks.diary = _diaryFocus;
    TodayHooks.routines = _routinesFocus;
    TodayHooks.saveDiary = _saveDiaryEntry;
    TodayHooks.markNextDone = _markNextDone;
    _loadUserAdapt();
    _refreshDoneToday();
  }

  /// Next open item for the hero card (special first, then first open routine).
  String? get _nextHeroTitle {
    if (_specialOrders.isNotEmpty) return _specialOrders.first.title;
    for (final r in _todayRoutines) {
      if (!_doneTodayIds.contains(r.id) &&
          !_skippedTodayIds.contains(r.id)) {
        return r.title;
      }
    }
    return null;
  }

  String get _nextHeroEmoji {
    if (_specialOrders.isNotEmpty) {
      return _specialOrders.first.disruptive ? '📌' : '✨';
    }
    return '🌿';
  }

  Future<void> _refreshDoneToday() async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final logs = await IsarService.getLogsForDate(todayStr);
    final trusted = await IsarService.getTrustedDevices();
    final steps = await IsarService.stepProgressForDate(todayStr);
    final settings = await IsarService.getSettings();
    final specials = await IsarService.getSpecialOrdersForDate(todayStr);
    if (!mounted) return;
    setState(() {
      _doneTodayIds = logs
          .where((l) => l.status == CompletionStatus.done)
          .map((l) => l.routineId)
          .toSet();
      _skippedTodayIds = logs
          .where((l) => l.status == CompletionStatus.skipped)
          .map((l) => l.routineId)
          .toSet();
      _stepProgress = steps;
      _nextFirstOrder = settings.todayOrder == 'next';
      _specialOrders = specials;
      _lastSyncLine = trusted.isEmpty
          ? null
          : 'Last synced across devices: ${trusted.map((d) => d.lastSyncedAt).reduce((a, b) => a.isAfter(b) ? a : b).toLocal().toString().substring(0, 16)}';
    });
  }

  /// Sometimes re-teach long-press (fog erases affordances). Not every day.
  bool get _showLongPressHint {
    final day = DateTime.now().day;
    return day % 3 == 0 || day % 3 == 1;
  }

  bool get _hasDisruptiveSpecial =>
      _specialOrders.any((e) => e.disruptive);

  /// Two ways to see the day (owner, 2026-07-08): morning→night (default,
  /// the calm timeline) or "what's next" — the closest upcoming task from
  /// right now first, so 18:18 shows the 18:30 thing on top. Done items
  /// sink to the bottom in both.
  void _sortForToday(List<Routine> list) {
    int minutes(Routine r) {
      if (r.time == null) return 24 * 60; // timeless tasks go last
      final p = r.time!.split(':');
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
    list.sort((a, b) {
      final aDone = _doneTodayIds.contains(a.id) ||
          _skippedTodayIds.contains(a.id);
      final bDone = _doneTodayIds.contains(b.id) ||
          _skippedTodayIds.contains(b.id);
      if (aDone != bDone) return aDone ? 1 : -1; // handled sinks
      final am = minutes(a), bm = minutes(b);
      if (!_nextFirstOrder) return am.compareTo(bm);
      // "What's next": upcoming (>= now) first by nearness, then the
      // earlier-today ones, then timeless.
      int rank(int m) => m >= 24 * 60 ? 2 : (m >= nowMin ? 0 : 1);
      final ra = rank(am), rb = rank(bm);
      if (ra != rb) return ra.compareTo(rb);
      return am.compareTo(bm);
    });
  }

  Future<void> _toggleTodayOrder() async {
    final s = await IsarService.getSettings();
    final next = !_nextFirstOrder;
    await IsarService.updateSettings(
        s.copyWith(todayOrder: next ? 'next' : 'timeline'));
    if (!mounted) return;
    setState(() => _nextFirstOrder = next);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(next
            ? 'Showing what\'s next first. The order follows the clock.'
            : 'Showing the whole day, morning to night.')));
  }

  /// One more part of this routine handled — quiet micro-win. When the last
  /// part lands, mark the whole routine done (quiet ✓, always reversible).
  Future<void> _advanceStep(Routine r) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final done =
        await IsarService.advanceStep(r.id, todayStr, r.steps.length);
    await _refreshDoneToday();
    if (done >= r.steps.length && mounted) {
      await _toggleComplete(r); // quiet done — tap again to open if needed
    }
  }

  Future<void> _loadUserAdapt() async {
    final s = await IsarService.getSettings();
    final mad = await IsarService.isMadModeActive();
    final gap = s.daysSinceLastOpen;
    final welcome = gap != null && gap >= 3;
    // Touch lastOpenedAt so the next gap is measured from this open.
    await IsarService.updateSettings(
        s.copyWith(lastOpenedAt: DateTime.now()));
    if (mounted) {
      setState(() {
        _userType = s.userType;
        _madActive = mad;
        _guidedMode = s.guidedMode;
        _fogReading = s.fogReading;
        _welcomeBack = welcome;
      });
      // Reassurance, never alarm: every change was already saved as it
      // happened, so an ungentle close costs nothing. Say so once.
      if (!IsarService.lastExitWasClean && !_uncleanExitNoticeShown) {
        _uncleanExitNoticeShown = true;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 6),
          content: Text(
              'Last time didn\'t close gently — no worries. Everything was already saved as you went. Nothing lost.'),
        ));
      }
      if (!s.hasSeenListTutorial && !_guidedMode) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _showListTutorial());
      }
    }
  }

  double get _textScale {
    if (_fogReading) return 1.28;
    if (_userType.contains('kid') || _userType == 'ADHD') return 1.2;
    if (_userType == 'custom (penguin)') return 1.15;
    return 1.0;
  }

  void _showListTutorial() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('How your list works'),
        content: const Text(
          'Tap a step when it is done — you get a quiet ✓.\n\n'
          'Long-press a step for “Not today”. No reason needed. '
          'A note is optional.\n\n'
          '“Something different” is for days that break the usual plan '
          '(a trip, a fix, a long drive).',
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              final s = await IsarService.getSettings();
              await IsarService.updateSettings(
                  s.copyWith(hasSeenListTutorial: true));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _confetti.dispose();
    _diaryController.dispose();
    if (TodayHooks.diary == _diaryFocus) TodayHooks.diary = null;
    if (TodayHooks.routines == _routinesFocus) TodayHooks.routines = null;
    TodayHooks.saveDiary = null;
    TodayHooks.markNextDone = null;
    _diaryFocus.dispose();
    _routinesFocus.dispose();
    super.dispose();
  }

  /// Turn "I am mad" mode on/off. On = 24h of validated rage; vents made in
  /// this mode burn out within ~2 days. Never held against the user.
  Future<void> _toggleMad() async {
    final newVal = !_madActive;
    await IsarService.setMadMode(newVal);
    if (!mounted) return;
    setState(() => _madActive = newVal);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newVal
            ? 'Mad mode on. Say anything — it burns out by itself.'
            : 'Welcome back. Nothing you said is held against you.'),
      ),
    );
  }

  /// Complete the next unfinished routine (used by FAB and the mark_done keybind).
  Future<void> _markNextDone() async {
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final routines = await IsarService.getAllRoutines();
    final logs = await IsarService.getLogsForDate(todayStr);
    final handled = logs.map((l) => l.routineId).toSet();
    final todayR =
        routines.where((r) => r.appliesOn(today) && r.isActive).toList();
    for (final r in todayR) {
      if (!handled.contains(r.id)) {
        await _toggleComplete(r);
        return;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Everything for today is already done. Amazing!')),
      );
    }
  }

  /// Arrow keys move, Enter/Space completes, S opens skip-with-reason,
  /// Escape releases focus. Selection is shown with the teal highlight.
  KeyEventResult _handleListKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_todayRoutines.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() =>
          _kbSelected = (_kbSelected + 1).clamp(0, _todayRoutines.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() =>
          _kbSelected = (_kbSelected - 1).clamp(0, _todayRoutines.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      if (_kbSelected >= 0 && _kbSelected < _todayRoutines.length) {
        // Toggle always: done/skip → open again, open → done. Never trapped.
        _toggleComplete(_todayRoutines[_kbSelected]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      if (_kbSelected >= 0 && _kbSelected < _todayRoutines.length) {
        final r = _todayRoutines[_kbSelected];
        if (!_doneTodayIds.contains(r.id)) {
          _openDidntHappenSheet(r);
        }
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _routinesFocus.unfocus();
      setState(() => _kbSelected = -1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Tap the row: open → done, or handled → open again.
  /// ALWAYS reversible (owner, 2026-07-20): a wrong ✓ or "not today" must
  /// never trap anyone — irreversible marks drive people away from the app.
  /// Quiet ✓ when marking done (AGENTS: no follow-up question). Notes stay
  /// behind long-press. One soft line only when undoing.
  Future<void> _toggleComplete(Routine r) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isDone = _doneTodayIds.contains(r.id);
    final isSkipped = _skippedTodayIds.contains(r.id);
    if (!mounted) return;

    if (isDone || isSkipped) {
      // Open again — no "are you sure?", no shame. Instant undo.
      await IsarService.removeCompletion(routineId: r.id, date: todayStr);
      ref.invalidate(routinesProvider);
      await _refreshDoneToday();
      AndroidBnsWidget.updateWidget();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Open again. That\'s fine. 🌿'),
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    // Marking done: if they left a help-note, show it once (note stays either way).
    final allCaptures = await IsarService.getAllCaptures();
    final problemNote = allCaptures
        .where((c) =>
            c.linkedRoutineId == r.id &&
            c.tags.contains('need-help') &&
            c.deletedAt == null)
        .fold<QuickCapture?>(
            null, (best, c) => best == null || c.at.isAfter(best.at) ? c : best);
    if (!mounted) return;

    if (problemNote != null) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(r.title),
          content: Text('You wrote about this one:\n\n'
              '“${problemNote.text ?? problemNote.contextNote ?? ''}”\n\n'
              'The note stays either way. Mark done?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Not yet')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Done ✓ — keep the note')),
          ],
        ),
      );
      if (sure != true) return;
    }

    await IsarService.logCompletion(
      routineId: r.id,
      date: todayStr,
      status: CompletionStatus.done,
    );
    final settings = await IsarService.getSettings();
    if (!settings.quietMode) {
      _confetti.play();
    }

    ref.invalidate(routinesProvider);
    await _refreshDoneToday();
    AndroidBnsWidget.updateWidget();
    // Quiet ✓ — no snackbar, no "good job you finished" pressure.
  }

  Future<bool> _isDoneToday(String routineId, String date) async {
    final logs = await IsarService.getLogsForDate(date);
    return logs.any(
        (l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  /// Long-press = "not today" (owner, 2026-07-20). One tap is enough —
  /// no reason required. Optional note after / beside, never a tax.
  void _openDidntHappenSheet(Routine r) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final noteCtrl = TextEditingController();
    var noteSaved = false;

    Future<void> saveProblemNote() async {
      final text = noteCtrl.text.trim();
      if (text.isEmpty || noteSaved) return;
      noteSaved = true;
      await IsarService.addCapture(QuickCapture(
        id: '',
        at: DateTime.now(),
        text: text,
        linkedRoutineId: r.id,
        tags: const ['routine', 'need-help'],
        memoryLevel: MemoryLevel.remember,
        contextNote: 'Note about: ${r.title}',
      ));
    }

    Future<void> markNotToday({bool withNote = false}) async {
      if (withNote) await saveProblemNote();
      await IsarService.logCompletion(
        routineId: r.id,
        date: todayStr,
        status: CompletionStatus.skipped,
      );
      ref.invalidate(routinesProvider);
      await _refreshDoneToday();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 40 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Not today is fine. No reason needed.',
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () async {
                // One tap: log didn't, leave. Note field only if they filled it.
                await markNotToday(withNote: true);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Not today', style: TextStyle(fontSize: 17)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Want to leave a note? Optional — only if you feel like it.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Anything you want remembered…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            QuickCaptureBar(
              onTap: () async {
                await markNotToday();
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  context.push('/capture', extra: {
                    'linkedRoutineId': r.id,
                    'tags': ['need-help'],
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(saveProblemNote);
  }

  /// Something out of the ordinary — create or edit a special order.
  void _openSpecialOrderSheet({CalendarEvent? existing}) {
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final companionCtrl =
        TextEditingController(text: existing?.companionNote ?? '');
    final notesCtrl = TextEditingController(text: existing?.notes ?? '');
    final today = DateTime.now();
    DateTime start;
    try {
      start = existing != null
          ? DateTime.parse(existing.date)
          : DateTime(today.year, today.month, today.day);
    } catch (_) {
      start = DateTime(today.year, today.month, today.day);
    }
    DateTime? end;
    if (existing?.endDate != null) {
      end = DateTime.tryParse(existing!.endDate!);
    }
    var disruptive = existing?.disruptive ?? true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 24, 24, 40 + MediaQuery.of(ctx).viewInsets.bottom),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        existing == null
                            ? 'Something different'
                            : 'Edit this day item',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(
                      'Not a usual routine — a trip, a fix, a day that '
                      'breaks the system. It will show on your list.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleCtrl,
                      autofocus: existing == null,
                      decoration: const InputDecoration(
                        labelText: 'What is it?',
                        hintText: 'e.g. Drop off laptop · Drive to…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          'Starts ${DateFormat.MMMd().format(start)}'),
                      trailing: const Icon(Icons.event),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: start,
                          firstDate:
                              today.subtract(const Duration(days: 20)),
                          lastDate: today.add(const Duration(days: 400)),
                        );
                        if (picked != null) {
                          setSheet(() {
                            start = picked;
                            if (end != null && end!.isBefore(start)) {
                              end = start;
                            }
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(end == null
                          ? 'One day only (tap to add more days)'
                          : 'Until ${DateFormat.MMMd().format(end!)}'),
                      trailing: const Icon(Icons.date_range),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: end ?? start,
                          firstDate: start,
                          lastDate: today.add(const Duration(days: 400)),
                        );
                        if (picked != null) {
                          setSheet(() => end = picked);
                        }
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('This breaks the usual day'),
                      subtitle: const Text(
                          'Usual list can wait while this is on'),
                      value: disruptive,
                      onChanged: (v) => setSheet(() => disruptive = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: companionCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Who is with you? (optional)',
                        hintText: 'e.g. Parents are coming',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        final now = DateTime.now();
                        final event = CalendarEvent(
                          id: existing?.id ?? '',
                          title: title,
                          date: ymd(start),
                          endDate: end != null &&
                                  ymd(end!) != ymd(start)
                              ? ymd(end!)
                              : null,
                          isAllDay: true,
                          isSpecialOrder: true,
                          disruptive: disruptive,
                          companionNote:
                              companionCtrl.text.trim().isEmpty
                                  ? null
                                  : companionCtrl.text.trim(),
                          notes: notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                          createdAt: existing?.createdAt ?? now,
                          updatedAt: now,
                        );
                        if (existing == null) {
                          await IsarService.addEvent(event);
                        } else {
                          await IsarService.updateEvent(event);
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _refreshDoneToday();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(existing == null
                                  ? 'On your list. You\'ve got this. 🌿'
                                  : 'Updated. 🌿'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: Text(existing == null
                          ? 'Put it on my day'
                          : 'Save changes'),
                    ),
                    if (existing != null) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (c) => AlertDialog(
                              title: const Text('Remove from the list?'),
                              content: const Text(
                                  'It will leave the day. You can always add a new one.'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(c, false),
                                    child: const Text('Keep it')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(c, true),
                                    child: const Text('Remove')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await IsarService.deleteEvent(existing.id);
                            if (ctx.mounted) Navigator.pop(ctx);
                            await _refreshDoneToday();
                          }
                        },
                        child: const Text('Remove from list'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveDiaryEntry() async {
    final text = _diaryController.text.trim();
    if (text.isEmpty) return;

    // Save as diary capture - interactive moving diary
    final capture = QuickCapture(
      id: '',
      at: DateTime.now(),
      text: text,
      tags: ['diary', 'goal-progress'],
      memoryLevel: MemoryLevel.remember,
      contextNote: 'Daily interactive diary - goals & wins',
    );
    await IsarService.addCapture(capture);
    _diaryController.clear();
    ref.invalidate(routinesProvider);
    AndroidBnsWidget.updateWidget();

    if (mounted) {
      // Brief and quiet — the person already chose to keep it; don't ask
      // again. (Promoting a memory to "keep forever" lives in Memories.)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('In the diary. ✓'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routinesAsync = ref.watch(routinesProvider);
    final today = DateTime.now();
    // On wide PC windows the sidebar already handles navigation — hide the
    // duplicate nav buttons below to keep the screen calm and focused.
    final isDesktopWide =
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
            MediaQuery.sizeOf(context).width >= 820;

    return Scaffold(
      appBar: BnsAppBar(
        title: 'Today • BNS',
        leading: Image.asset('assets/icon/bns_logo.png', height: 28, width: 28),
        centerTitle: false,
        hideOnDesktopWide:
            true, // modern PC sidebar handles navigation chrome + marked selection
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Calendar',
            onPressed: () => context.push('/calendar'),
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Sync your devices',
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: 'Memories',
            onPressed: () => context.push('/memories'),
          ),
        ],
      ),
      // Safe areas + bottom padding so FAB never covers the list on phones.
      body: SafeArea(
        child: Stack(
        children: [
          // Comfortable reading column on big monitors; full width on phones.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  // Wrap on narrow phones so "I'm mad" never collides with the headline.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width > 420
                              ? 520
                              : MediaQuery.sizeOf(context).width - 48,
                        ),
                        child: Text(
                          _madActive
                              ? 'It\'s okay to be furious. This space can take it.'
                              : 'Hey — whatever today looks like is okay.',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 22 * _textScale),
                        ),
                      ),
                      if (!_madActive)
                        TextButton.icon(
                          onPressed: _toggleMad,
                          icon: const Icon(Icons.whatshot_outlined, size: 18),
                          label: const Text('I\'m mad'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _madActive
                        ? 'Rage is part of the marathon too. Skipping today on purpose still counts.'
                        : 'Routines support you. They never get mad.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 16 * _textScale,
                        ),
                  ),
                  // Rediscovery: calm return after a gap (folder on the desk).
                  if (_welcomeBack)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withOpacity(0.55),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Text('💚', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your day is here. Glad you found your way back. '
                                  'No rush — start wherever feels light.',
                                  style: TextStyle(
                                    fontSize: 14 * _textScale,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Dismiss',
                                onPressed: () =>
                                    setState(() => _welcomeBack = false),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Next-on-day hero — one calm primary line.
                  if (_nextHeroTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Card(
                        color: Theme.of(context)
                            .colorScheme
                            .secondaryContainer
                            .withOpacity(0.4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Text(_nextHeroEmoji,
                                  style: const TextStyle(fontSize: 26)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'What\'s next',
                                      style: TextStyle(
                                        fontSize: 12 * _textScale,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer
                                            .withOpacity(0.8),
                                      ),
                                    ),
                                    Text(
                                      _nextHeroTitle!,
                                      style: TextStyle(
                                        fontSize: 18 * _textScale,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer,
                                      ),
                                    ),
                                    Text(
                                      'Whenever you\'re ready 🌿',
                                      style: TextStyle(
                                        fontSize: 13 * _textScale,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer
                                            .withOpacity(0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_madActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.whatshot,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Mad mode is on. Curse everyone and everything — only you see it, and vents burn out on their own within ~2 days. Being here while angry is still showing up.',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onErrorContainer),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        context.push('/capture', extra: {
                                      'tags': ['mad-vent'],
                                    }),
                                    icon: const Icon(Icons.record_voice_over),
                                    label:
                                        const Text('Vent now — voice or text'),
                                  ),
                                  TextButton(
                                    onPressed: _toggleMad,
                                    child: const Text('Calm again'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Gentle awareness of sync status (helps memory).
                  // Cached in state — rebuilds must stay synchronous.
                  if (_lastSyncLine != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 12),
                      child: Text(
                        _lastSyncLine!,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 28),

                  Text('Today\'s gentle steps',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (isDesktopWide)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Keyboard: Ctrl+G jumps here • ↑↓ move • Enter = done • S = not today',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  // Fog erases affordances — re-teach long-press sometimes.
                  if (_showLongPressHint)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Tip: long-press a step if you want to leave a note. '
                        'Not today needs no reason.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),

                  // Special orders (out of the ordinary) — top of the day.
                  if (_specialOrders.isNotEmpty) ...[
                    if (_hasDisruptiveSpecial)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          color: Theme.of(context)
                              .colorScheme
                              .tertiaryContainer
                              .withOpacity(0.55),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              'Something different is on today. '
                              'The usual list can wait. 🌿',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onTertiaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    for (final so in _specialOrders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SpecialOrderCard(
                          event: so,
                          onTap: _guidedMode
                              ? null
                              : () => _openSpecialOrderSheet(existing: so),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],

                  if (!_guidedMode)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () => _openSpecialOrderSheet(),
                            icon: const Icon(Icons.explore_outlined, size: 18),
                            label: const Text('Something different'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push('/capture', extra: {
                              'doctorVisit': true,
                              'tags': ['doctor-visit', 'family'],
                            }),
                            icon: const Icon(Icons.local_hospital_outlined,
                                size: 18),
                            label: const Text('Doctor visit'),
                          ),
                        ],
                      ),
                    ),

                  routinesAsync.when(
                    data: (routines) {
                      final todaysRoutines = routines
                          .where((r) => r.appliesOn(today) && r.isActive)
                          .toList();
                      _sortForToday(todaysRoutines);
                      _todayRoutines =
                          todaysRoutines; // for the keyboard handler

                      if (todaysRoutines.isEmpty &&
                          _specialOrders.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_guidedMode
                                  ? 'Nothing on the list right now. All is well. 🌿'
                                  : 'Nothing scheduled for today — that\'s perfectly fine.'),
                              if (!_guidedMode) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () => context.push('/routines'),
                                  icon: const Icon(Icons.add),
                                  label: const Text(
                                      'Add a routine when you\'re ready'),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      if (todaysRoutines.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // Focusable list: Ctrl+G (or Tab) reaches it, arrows move the
                      // teal selection, Enter completes, S opens not-today sheet.
                      return Focus(
                        focusNode: _routinesFocus,
                        onKeyEvent: (node, event) => _handleListKey(event),
                        onFocusChange: (hasFocus) {
                          setState(() {
                            if (hasFocus &&
                                _kbSelected < 0 &&
                                todaysRoutines.isNotEmpty) {
                              _kbSelected = 0;
                            }
                            if (!hasFocus) _kbSelected = -1;
                          });
                        },
                        child: Column(
                          children: [
                            // Order choice: the calm timeline (default) or
                            // "what's next from right now". Hidden in guided mode.
                            if (!_guidedMode)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _toggleTodayOrder,
                                  icon: Icon(
                                      _nextFirstOrder
                                          ? Icons.schedule
                                          : Icons.wb_twilight,
                                      size: 16),
                                  label: Text(
                                      _nextFirstOrder
                                          ? 'Showing: what\'s next'
                                          : 'Showing: morning to night',
                                      style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            for (int i = 0; i < todaysRoutines.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: RoutineTile(
                                  routine: todaysRoutines[i],
                                  isDone: _doneTodayIds
                                      .contains(todaysRoutines[i].id),
                                  isSkipped: _skippedTodayIds
                                      .contains(todaysRoutines[i].id),
                                  big: _guidedMode,
                                  softened: _hasDisruptiveSpecial,
                                  stepsDone: _stepProgress[
                                          todaysRoutines[i].id] ??
                                      0,
                                  onStepDone: todaysRoutines[i]
                                          .steps.isNotEmpty
                                      ? () =>
                                          _advanceStep(todaysRoutines[i])
                                      : null,
                                  selected: _routinesFocus.hasFocus &&
                                      i == _kbSelected,
                                  onToggle: () =>
                                      _toggleComplete(todaysRoutines[i]),
                                  onSkip: () =>
                                      _openDidntHappenSheet(todaysRoutines[i]),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error loading: $e'),
                  ),

                  const SizedBox(height: 24),

                  // The diary: one calm box, no presets, no double-asking.
                  // (Copy is for the person, never for the developer.)
                  // Guided mode (level 4): no building, no diary box —
                  // only the list; words go through long-press or capture.
                  if (!_guidedMode) ...[
                    Text('Diary',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'A good thing, a hard thing — both belong here.',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _diaryController,
                      focusNode: _diaryFocus,
                      maxLines: 3, // more robust typing area on PC
                      minLines: 2,
                      decoration: InputDecoration(
                        hintText: 'How is today going?',
                        helperText: isDesktopWide ? 'Ctrl+D jumps here' : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      onPressed: _saveDiaryEntry,
                      icon: const Icon(Icons.check),
                      label: const Text('Keep in diary'),
                    ),
                  ],

                  const SizedBox(height: 24),
                  QuickCaptureBar(
                    onTap: () => context.push('/capture'),
                  ),
                  // On PC the sidebar covers navigation — these stay for mobile.
                  // Guided mode: the calendar stays (visual, read-mostly);
                  // managing routines is the inspector's job, not shown here.
                  if (!isDesktopWide) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/calendar'),
                      icon: const Icon(Icons.event_note),
                      label: const Text(
                          'Open calendar for appointments & day notes'),
                    ),
                    const SizedBox(height: 8),
                    if (!_guidedMode)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/routines'),
                      icon: const Icon(Icons.list_alt),
                      label:
                          const Text('Manage all routines (add, edit, delete)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/memories'),
                      icon: const Icon(Icons.psychology),
                      label: const Text(
                          'Memory section: Remember & Memorize what happened'),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              shouldLoop: false,
              numberOfParticles: 28,
              colors: const [
                Color(0xFF14B8A6),
                Color(0xFF8B5CF6),
                Color(0xFFFDE047),
                Color(0xFFFB923C),
              ],
            ),
          ),
        ],
      ),
      ),
      // Compact on narrow phones so it never collides with content edges.
      floatingActionButton: LayoutBuilder(
        builder: (context, _) {
          final narrow = MediaQuery.sizeOf(context).width < 360;
          return FloatingActionButton.extended(
            onPressed: _markNextDone,
            label: Text(narrow ? 'Next ✓' : 'Mark next step done'),
            icon: const Icon(Icons.check_rounded),
          );
        },
      ),
    );
  }
}

/// Calm card for an out-of-the-ordinary day item (special order).
class _SpecialOrderCard extends StatelessWidget {
  final CalendarEvent event;
  final VoidCallback? onTap;

  const _SpecialOrderCard({required this.event, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final end = event.endDate;
    final span = end != null && end != event.date
        ? ' · until ${DateFormat.MMMd().format(DateTime.parse(end))}'
        : '';
    return Card(
      color: cs.secondaryContainer.withOpacity(0.45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.disruptive ? '📌' : '✨',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Something different$span'
                      '${onTap != null ? ' · tap to edit' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSecondaryContainer.withOpacity(0.8),
                      ),
                    ),
                    if (event.companionNote != null &&
                        event.companionNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'With you: ${event.companionNote}',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ],
                    if (event.notes != null &&
                        event.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.notes!,
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSecondaryContainer.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
