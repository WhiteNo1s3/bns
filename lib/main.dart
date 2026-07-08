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
  String? _lastSyncLine; // cached "last synced" note (no per-frame queries)

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

  Future<void> _refreshDoneToday() async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final logs = await IsarService.getLogsForDate(todayStr);
    final trusted = await IsarService.getTrustedDevices();
    if (!mounted) return;
    setState(() {
      _doneTodayIds = logs
          .where((l) => l.status == CompletionStatus.done)
          .map((l) => l.routineId)
          .toSet();
      _lastSyncLine = trusted.isEmpty
          ? null
          : 'Last synced across devices: ${trusted.map((d) => d.lastSyncedAt).reduce((a, b) => a.isAfter(b) ? a : b).toLocal().toString().substring(0, 16)}';
    });
  }

  Future<void> _loadUserAdapt() async {
    final s = await IsarService.getSettings();
    final mad = await IsarService.isMadModeActive();
    if (mounted) {
      setState(() {
        _userType = s.userType;
        _madActive = mad;
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
    }
  }

  double get _textScale {
    if (_userType.contains('kid') || _userType == 'ADHD') return 1.2;
    if (_userType == 'custom (penguin)') return 1.15;
    return 1.0;
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
    final todayR =
        routines.where((r) => r.appliesOn(today) && r.isActive).toList();
    for (final r in todayR) {
      if (!await _isDoneToday(r.id, todayStr)) {
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
        _toggleComplete(_todayRoutines[_kbSelected]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      if (_kbSelected >= 0 && _kbSelected < _todayRoutines.length) {
        _openSkipSheet(_todayRoutines[_kbSelected]);
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

  Future<void> _toggleComplete(Routine r) async {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final isDone = await _isDoneToday(r.id, todayStr);

    await IsarService.logCompletion(
      routineId: r.id,
      date: todayStr,
      status: isDone ? CompletionStatus.skipped : CompletionStatus.done,
    );

    if (!isDone) {
      final settings = await IsarService.getSettings();
      if (!settings.quietMode) {
        _confetti.play();
      }
    }

    // Refresh
    ref.invalidate(routinesProvider);
    await _refreshDoneToday();

    // Update Android widget (gadget) with fresh data
    AndroidBnsWidget.updateWidget();

    // Celebrate first, offer second — never block the happy moment with a dialog.
    if (!isDone && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${r.title}" done — you made it!'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Remember this moment',
            onPressed: () => _router.push('/capture', extra: {
              'linkedRoutineId': r.id,
              'initialText': 'What happened in this routine today? Why?',
            }),
          ),
        ),
      );
    }
  }

  Future<bool> _isDoneToday(String routineId, String date) async {
    final logs = await IsarService.getLogsForDate(date);
    return logs.any(
        (l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  void _openSkipSheet(Routine r) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No pressure at all.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
                'Skipping on purpose is a decision — and deciding counts as a win.'),
            const SizedBox(height: 4),
            const Text(
                'It can help to capture why. Voice or text — or just close.'),
            const SizedBox(height: 20),
            QuickCaptureBar(
              onTap: () {
                Navigator.pop(ctx);
                context.push('/capture', extra: {
                  'linkedRoutineId': r.id,
                  'initialText': 'Reason for today / what happened: ',
                });
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await IsarService.logCompletion(
                  routineId: r.id,
                  date: todayStr,
                  status: CompletionStatus.skipped,
                );
                ref.invalidate(routinesProvider);
              },
              child: const Text('Close — no need to explain'),
            ),
          ],
        ),
      ),
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
      // One friendly toast with an optional action — no dialog interrupting the win.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Saved to diary — no win is too small. You made it!'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Keep forever',
            onPressed: () async {
              final memCap = QuickCapture(
                id: '',
                at: DateTime.now(),
                text: text,
                tags: ['diary', 'memorize-win', 'good'],
                memoryLevel: MemoryLevel.memorize,
                contextNote: 'Permanent diary win - you did it!',
              );
              await IsarService.addCapture(memCap);
            },
          ),
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
      body: Stack(
        children: [
          // Comfortable reading column on big monitors; unchanged on mobile.
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
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
                        'Keyboard: Ctrl+G jumps here • ↑↓ move • Enter = done • S = skip with reason',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  const SizedBox(height: 10),

                  routinesAsync.when(
                    data: (routines) {
                      final todaysRoutines = routines
                          .where((r) => r.appliesOn(today) && r.isActive)
                          .toList();
                      _todayRoutines =
                          todaysRoutines; // for the keyboard handler

                      if (todaysRoutines.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                  'Nothing scheduled for today — that\'s perfectly fine.'),
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                onPressed: () => context.push('/routines'),
                                icon: const Icon(Icons.add),
                                label: const Text(
                                    'Add a routine when you\'re ready'),
                              ),
                            ],
                          ),
                        );
                      }

                      // Focusable list: Ctrl+G (or Tab) reaches it, arrows move the
                      // teal selection, Enter completes, S opens skip-with-reason.
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
                            // Synchronous done-state from the cached set —
                            // stable frames, nothing async during rebuilds.
                            for (int i = 0; i < todaysRoutines.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: RoutineTile(
                                  routine: todaysRoutines[i],
                                  isDone: _doneTodayIds
                                      .contains(todaysRoutines[i].id),
                                  selected: _routinesFocus.hasFocus &&
                                      i == _kbSelected,
                                  onToggle: () =>
                                      _toggleComplete(todaysRoutines[i]),
                                  onSkip: () =>
                                      _openSkipSheet(todaysRoutines[i]),
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

                  // Interactive Moving Diary integration
                  Text('Moving Diary - Remind & Set Goals, Mark V for Done',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Set goals, note wins. Every step forward counts — big or small, we applaud any progress.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _diaryController,
                    focusNode: _diaryFocus,
                    maxLines: 3, // more robust typing area on PC
                    minLines: 2,
                    decoration: const InputDecoration(
                      hintText:
                          'Today\'s goal or win... (typing is #1 on PC — use Ctrl+D to focus)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ElevatedButton.icon(
                    onPressed: _saveDiaryEntry,
                    icon: const Icon(Icons.check),
                    label: const Text('Save to Diary (V = done! You made it)'),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          _diaryController.text =
                              'Small win: got out of bed / brushed teeth';
                          _saveDiaryEntry();
                        },
                        child: const Text('V: got out of bed'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          _diaryController.text =
                              'Progress: used the toilet properly today';
                          _saveDiaryEntry();
                        },
                        child: const Text('V: toilet progress'),
                      ),
                      OutlinedButton(
                        onPressed: () {
                          _diaryController.text = 'I showed up today.';
                          _saveDiaryEntry();
                        },
                        child: const Text('V: I showed up'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  QuickCaptureBar(
                    onTap: () => context.push('/capture'),
                  ),
                  // On PC the sidebar covers navigation — these stay for mobile.
                  if (!isDesktopWide) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/calendar'),
                      icon: const Icon(Icons.event_note),
                      label: const Text(
                          'Open calendar for appointments & day notes'),
                    ),
                    const SizedBox(height: 8),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _markNextDone,
        label: const Text('Mark next step done'),
        icon: const Icon(Icons.check_rounded),
      ),
    );
  }
}
