import 'dart:async' show Timer;
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // for LogicalKeyboardKey
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/ui/layout.dart';
import 'package:bns/ui/theme.dart';
import 'package:bns/core/keybinds.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/providers/app_providers.dart';
import 'package:bns/core/day_items.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/ui/widgets/routine_tile.dart';
import 'package:bns/ui/widgets/plan_tile.dart';
import 'package:bns/ui/widgets/next_hero_card.dart';
import 'package:bns/ui/widgets/quick_capture_bar.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/bns_desktop_shell.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/features/calendar/calendar_screen.dart';
import 'package:bns/features/sync/sync_screen.dart';
import 'package:bns/features/routines/routines_screen.dart';
import 'package:bns/features/memory/memories_screen.dart';
import 'package:bns/features/diary/day_thread_screen.dart';
import 'package:bns/features/caregiver/caregiver_home_screen.dart';
import 'package:home_widget/home_widget.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/sync/lan_sync_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/desktop_reminder_service.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/services/file_handler.dart';
import 'package:bns/features/sync/pairing_dialogs.dart';
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
  // Hebrew dates for DateFormat (weekday names on tiles etc.) — loaded
  // after the first frame, same sacred-first-frame law as everything else.
  initializeDateFormatting('he').catchError((_) {});
}

Future<void> _startupChores(List<String> args) async {
  try {
    // A tapped reminder lands where it points: Today, or the plan's day.
    NotificationsService.onOpen = (route) => _router.go(route);
    // Reminders follow the data by themselves: any persisted change —
    // an edited routine, a new plan, a LAN sync, a .bns import — quietly
    // refreshes the schedule (debounced + fingerprinted, so it's free).
    // The same change also travels to trusted devices on the network —
    // the silky half of sync: nobody presses anything.
    IsarService.onDataChanged = () {
      NotificationsService.maybeRescheduleSoon();
      LanSyncService.instance.noteLocalDataChanged();
    };
    await NotificationsService.init();
    await NotificationsService.rescheduleAll();
  } catch (_) {
    // Reminders are a courtesy — the app runs fine without them today.
  }
  try {
    // Windows has no system notifications for Flutter yet — while the app
    // is open, a gentle in-app reminder card carries the moment instead.
    DesktopReminderService.start(onOpen: (route) => _router.go(route));
  } catch (_) {}
  try {
    // Prune old historical data to keep files small (2-week default rolling).
    // Future planning (calendar) is preserved. Routines stay.
    await IsarService.pruneOldData();
  } catch (_) {}
  try {
    // Desktop: double-clicking an associated .bns file passes its path here.
    BnsFileHandler.checkDesktopArgs(args, null);
  } catch (_) {}
  try {
    // A pairing request must reach the person on ANY screen — it used to
    // be answered only while the Sync screen was open, so "I pressed sync
    // on the phone and the PC did nothing" (owner QA, 2026-08-09).
    LanSyncService.instance.onPairRequest = (req) async {
      final ctx = _router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null) return null;
      return showDialog<String>(
        context: ctx,
        barrierDismissible: false,
        builder: (_) => EnterCodeDialog(peerName: req.deviceName),
      );
    };
    // Sync results surface wherever the person is — completions and
    // problems as gentle toasts; routine background chatter stays subtle.
    // Toasts REPLACE each other (never queue) and identical repeats are
    // dropped for a while — pressing Sync six times must not play six
    // toasts back-to-back (owner QA, 2026-08-10: "annoying").
    String? lastToast;
    DateTime lastToastAt = DateTime.fromMillisecondsSinceEpoch(0);
    LanSyncService.instance.progressStream.listen((p) {
      if (p.subtle) return;
      if (!p.isComplete && p.error == null) return;
      final text = p.error == null ? p.message : '${p.message}\n${p.error}';
      final now = DateTime.now();
      if (text == lastToast &&
          now.difference(lastToastAt) < const Duration(seconds: 10)) {
        return;
      }
      lastToast = text;
      lastToastAt = now;
      final messenger = DesktopReminderService.messengerKey.currentState;
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(text),
          duration: Duration(seconds: p.error == null ? 4 : 8),
          behavior: SnackBarBehavior.floating,
        ));
    });
    // SEAMLESS SYNC (owner, 2026-07-27: "we see too many seams... to take an
    // Alzheimer patient to work this out at level 3/4, we are in trouble").
    // Signing in IS the sync: discovery starts with the app and trusted
    // devices catch up by themselves, with nobody visiting a sync screen.
    await LanSyncService.instance.startForApp();
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
      // WHOSE HOME IS THIS? On a helper's device the front door opens onto
      // THEIR person's day — a caregiver landing on their own empty Today
      // was useless, and the routines that arrive by sync were never theirs
      // to tick. Same app, same release: one build knows both hats.
      builder: (context, state) => _wrapForDesktop(
          context, const _HomeForThisDevice(), state.uri.toString()),
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
            RoutinesScreen(
                openNewOnStart: extra['openNew'] == true,
                caregiverUnlock: extra['caregiver'] == true),
            state.uri.toString());
      },
    ),
    GoRoute(
      path: '/memories',
      builder: (context, state) => _wrapForDesktop(
          context, const MemoriesScreen(), state.uri.toString()),
    ),
    GoRoute(
      path: '/day',
      builder: (context, state) {
        final date = state.uri.queryParameters['date'];
        return _wrapForDesktop(
            context,
            DayThreadScreen(initialDate: date),
            state.uri.toString());
      },
    ),
  ],
);

/// Picks the front door for THIS device: the person's Today, or — when
/// this copy belongs to a helper — the day of the person they help.
/// Watches settings, so flipping the switch re-homes the app instantly.
class _HomeForThisDevice extends ConsumerWidget {
  const _HomeForThisDevice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).asData?.value;
    if (settings?.caregiverDevice == true) return const CaregiverHomeScreen();
    return const TodayScreen();
  }
}

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
        // Reliable zip-v2 save (verify + .prev). Only advance the revision
        // marker when the portable file is proven good — otherwise we retry
        // next pause/exit instead of pretending we imaged.
        await BnsExporter.exportLatestSnapshot();
      }
      _lastImagedRevision = rev;
    } catch (_) {
      // Live store is already safe on disk. Portable .bns keeps its last
      // verified copy (.prev / previous BNS_Latest). Do NOT bump revision.
    } finally {
      _imaging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hebrew first (owner, 2026-07-26): the app language rides Settings and
    // the whole tree — including direction, RTL for the holy tongue —
    // follows it live. Watching here means a language change re-skins the
    // app on the spot, no restart.
    final appSettings = ref.watch(settingsProvider).asData?.value;
    L.lang = appSettings?.appLanguage ?? L.lang;
    // DateFormat (weekday names on tiles, "EEE, MMM d") follows along.
    Intl.defaultLocale = L.isHebrew ? 'he' : 'en';

    final app = MaterialApp.router(
      title: 'BNS',
      debugShowCheckedModeBanner: false,
      // Windows in-app reminders appear through this from any screen.
      scaffoldMessengerKey: DesktopReminderService.messengerKey,
      locale: L.locale,
      supportedLocales: const [Locale('he'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
      // Samsung's navigation keys were sitting ON TOP of the bottom of
      // every screen (owner's phone, 2026-07-26). The app now ends where
      // the system's keys begin — everywhere, one rule. In level 4, a big
      // "Back to my day" travels along on every screen that isn't home.
      builder: (context, child) => SafeArea(
          top: false,
          child: _GuidedHomeShell(child: child ?? const SizedBox.shrink())),
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
/// Level 4's thread home: whenever the person is anywhere that isn't Today,
/// a BIG warm "Back to my day" rides the bottom of the screen (owner,
/// 2026-07-26: an arrow is not enough when arrows stopped meaning things).
/// One place, every screen — no page has to remember to offer the way back.
class _GuidedHomeShell extends StatefulWidget {
  final Widget child;
  const _GuidedHomeShell({required this.child});

  @override
  State<_GuidedHomeShell> createState() => _GuidedHomeShellState();
}

class _GuidedHomeShellState extends State<_GuidedHomeShell> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_recheck);
    _recheck();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_recheck);
    super.dispose();
  }

  Future<void> _recheck() async {
    final s = await IsarService.getSettings();
    final away =
        _router.routerDelegate.currentConfiguration.uri.path != '/';
    final show = s.guidedMode && away;
    if (mounted && show != _show) setState(() => _show = show);
  }

  void _goHome() {
    // Peel any pushed pages (day view and friends), then land on Today.
    _router.routerDelegate.navigatorKey.currentState
        ?.popUntil((r) => r.isFirst);
    _router.go('/');
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return widget.child;
    return Column(
      children: [
        Expanded(child: widget.child),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          color: Theme.of(context).colorScheme.surface,
          child: FilledButton.icon(
            onPressed: _goHome,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            icon: const Icon(Icons.home_rounded, size: 28),
            label: Text(L.t('Back to my day', 'חזרה ליום שלי')),
          ),
        ),
      ],
    );
  }
}

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
    case 'open_day':
      _router.go('/day');
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
  // "Didn't happen" is a tag, not a checkmark — the tiles show it as words.
  Set<String> _skippedTodayIds = const {};
  // routineId → the latest kept "why" from the last few days (and when it
  // was written), so seeing the task means meeting the note again.
  Map<String, String> _recentNoteText = const {};
  Map<String, String> _recentNoteWhen = const {};
  // Everything told about each routine (notes + recordings), newest first —
  // the little door at the end of the row opens onto this.
  Map<String, List<QuickCapture>> _keptByRoutine = const {};
  // Today's storms: the mad-vents of this day, kept and revisitable.
  List<QuickCapture> _madToday = const [];
  // Today's PLANS — one-time things (a doctor appointment, an errand) that
  // stand in the day with the weight of a step (owner, 2026-08-09).
  List<CalendarEvent> _todayPlans = const [];
  Map<String, int> _stepProgress = const {}; // routineId → parts done today
  bool _nextFirstOrder = false; // false = morning→night (default)
  bool _guidedMode = false; // level 4: only the list, inspector builds
  String? _lastSyncLine; // cached "last synced" note (no per-frame queries)
  // OWL TIME: the hour the person's day ends (0 = midnight). Everything
  // "today" on this screen goes through these two, so a 02:00 pill at
  // 01:30 still belongs to TONIGHT's list for a person with a 04:00 border.
  int _rolloverHour = 0;

  DateTime get _logicalToday => logicalDateOf(DateTime.now(), _rolloverHour);
  String get _todayKey => logicalDayKey(DateTime.now(), _rolloverHour);

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
    // Data can change UNDERNEATH this screen — a sync arriving, a .bns
    // imported. The person must see it instantly; a restart-to-refresh is
    // fine for a power user and impossible at level 4 (owner, 2026-08-10).
    IsarService.dataRevision.addListener(_onDataRevision);
  }

  Timer? _revisionDebounce;

  void _onDataRevision() {
    _revisionDebounce?.cancel();
    _revisionDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      ref.invalidate(routinesProvider);
      _refreshDoneToday();
    });
  }

  Future<void> _refreshDoneToday() async {
    // Settings first: the person's day border (owl time) decides which
    // date "today" even is before anything else is fetched.
    final settings = await IsarService.getSettings();
    _rolloverHour = settings.dayRolloverHour;
    final todayStr = _todayKey;
    final logs = await IsarService.getLogsForDate(todayStr);
    final trusted = await IsarService.getTrustedDevices();
    final steps = await IsarService.stepProgressForDate(todayStr);
    final todayPlans = await IsarService.getEventsForDate(todayStr);
    // The kept "why"s: need-help notes from the last few days, latest one
    // per routine. They ride the tiles so the reason is met, not searched.
    final captures = await IsarService.getAllCaptures();
    final noteFloor = DateTime.now().subtract(const Duration(days: 4));
    final noteText = <String, String>{};
    final noteWhen = <String, String>{};
    final latestAt = <String, DateTime>{};
    for (final c in captures) {
      final rid = c.linkedRoutineId;
      if (rid == null || !c.tags.contains('need-help')) continue;
      if (c.at.isBefore(noteFloor)) continue;
      final words = (c.text ?? c.transcript ?? c.contextNote ?? '').trim();
      if (words.isEmpty) continue;
      final prev = latestAt[rid];
      if (prev != null && !c.at.isAfter(prev)) continue;
      latestAt[rid] = c.at;
      noteText[rid] = words;
      noteWhen[rid] = _whenLabel(c.at);
    }
    // The skip record carries its own why now — the most reliable copy.
    for (final l in logs) {
      if (l.status != CompletionStatus.skipped) continue;
      final words = (l.reason ?? '').trim();
      if (words.isEmpty || words == 'See linked capture') continue;
      final prev = latestAt[l.routineId];
      if (prev != null && !l.at.isAfter(prev)) continue;
      latestAt[l.routineId] = l.at;
      noteText[l.routineId] = words;
      noteWhen[l.routineId] = _whenLabel(l.at);
    }
    // Everything told about each routine, and today's storms. captures come
    // newest-first from the store, so the lists stay in telling order.
    final kept = <String, List<QuickCapture>>{};
    final mad = <QuickCapture>[];
    final now = DateTime.now();
    for (final c in captures) {
      final rid = c.linkedRoutineId;
      if (rid != null) (kept[rid] ??= []).add(c);
      if (c.tags.contains('mad-vent') &&
          c.at.year == now.year &&
          c.at.month == now.month &&
          c.at.day == now.day) {
        mad.add(c);
      }
    }
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
      _recentNoteText = noteText;
      _recentNoteWhen = noteWhen;
      _keptByRoutine = kept;
      _madToday = mad;
      _todayPlans = todayPlans;
      _stepProgress = steps;
      _nextFirstOrder = settings.todayOrder == 'next';
      final lastSyncAt = trusted.isEmpty
          ? null
          : trusted
              .map((d) => d.lastSyncedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b)
              .toLocal()
              .toString()
              .substring(0, 16);
      _lastSyncLine = lastSyncAt == null
          ? null
          : L.t('Last synced across devices: $lastSyncAt',
              'סונכרן לאחרונה בין המכשירים: $lastSyncAt');
    });
  }

  /// The kept words about one thing — notes and recordings together,
  /// newest first, each with its moment. This answers "what did I already
  /// say, and to whom?" so a thing can be taken up again later.
  void _showKeptWords(String title, List<QuickCapture> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  L.t(
                      'Everything kept about this — nothing is lost, nothing '
                      'is judged. Tap ▶ to hear a recording again.',
                      'כל מה שנשמר על זה — שום דבר לא הולך לאיבוד, ואף אחד '
                      'לא שופט. אפשר ללחוץ ▶ כדי לשמוע הקלטה שוב.'),
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in items)
                      Builder(builder: (_) {
                        final words =
                            (c.text ?? c.transcript ?? c.contextNote ?? '')
                                .trim();
                        return ListTile(
                          leading: Icon(c.audioPath != null
                              ? Icons.mic
                              : Icons.notes),
                          title: Text(words.isEmpty
                              ? L.t('A voice-only moment (no words yet)',
                                  'רגע של קול בלבד (עוד בלי מילים)')
                              : words),
                          subtitle: Text(
                            DateFormat('EEE, MMM d · HH:mm').format(c.at) +
                                (c.contextNote != null && c.text != null
                                    ? '\n${c.contextNote}'
                                    : ''),
                          ),
                          isThreeLine:
                              c.contextNote != null && c.text != null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // The device voice READS the kept words —
                              // "showing the text to the person" includes
                              // the person who can't read it right now.
                              if (words.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.volume_up, size: 28),
                                  tooltip: L.t('Hear it read aloud',
                                      'לשמוע את זה בהקראה'),
                                  onPressed: () => TtsService.speak(words),
                                ),
                              if (c.audioPath != null)
                                IconButton(
                                  icon: const Icon(Icons.play_circle_filled,
                                      size: 32),
                                  tooltip: L.t(
                                      'Hear the recording (tap twice to stop)',
                                      'לשמוע את ההקלטה (לחיצה נוספת עוצרת)'),
                                  onPressed: () async {
                                    try {
                                      await AudioPlaybackService
                                          .toggle(c.audioPath!);
                                    } catch (_) {
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                          SnackBar(
                                              content: Text(L.t(
                                                  'The sound for this one is not on this device anymore.',
                                                  'הקול של ההקלטה הזאת כבר לא נמצא במכשיר הזה.'))));
                                    }
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// When a note was written, in day-words plus the time of day — readable
  /// to the person and the caregiver alike.
  static String _whenLabel(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final hm = DateFormat('HH:mm').format(at);
    if (day == today) return L.t('today $hm', 'היום $hm');
    if (day == today.subtract(const Duration(days: 1))) {
      return L.t('yesterday $hm', 'אתמול $hm');
    }
    return '${DateFormat('EEE').format(at)} $hm';
  }

  // (Day ordering lives in lib/core/day_items.dart now — routines and
  // plans woven by the same laws, testable on their own.)

  /// The day's tiles: routines and plans in their woven order. Keyboard
  /// selection follows the routine's position among ROUTINES (the arrows
  /// walk steps; plans answer to taps), so the highlight index counts only
  /// them.
  List<Widget> _dayTiles(List<Object> dayList) {
    final tiles = <Widget>[];
    var routineIndex = 0;
    for (final item in dayList) {
      if (item is Routine) {
        final r = item;
        final i = routineIndex++;
        tiles.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RoutineTile(
            routine: r,
            isDone: _doneTodayIds.contains(r.id),
            big: _guidedMode,
            stepsDone: _stepProgress[r.id] ?? 0,
            onStepDone: r.steps.isNotEmpty ? () => _advanceStep(r) : null,
            selected: _routinesFocus.hasFocus && i == _kbSelected,
            skippedToday: _skippedTodayIds.contains(r.id),
            recentNote: _recentNoteText[r.id],
            recentNoteWhen: _recentNoteWhen[r.id],
            keptCount: _keptByRoutine[r.id]?.length ?? 0,
            onShowKept: () =>
                _showKeptWords(r.title, _keptByRoutine[r.id] ?? const []),
            onToggle: () => _toggleComplete(r),
            onSkip: () => _openDidntHappenSheet(r),
          ),
        ));
      } else if (item is CalendarEvent) {
        tiles.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlanTile(
            plan: item,
            big: _guidedMode,
            onToggle: () => _togglePlanDone(item),
            onSkip: () => _openPlanDidntHappenSheet(item),
          ),
        ));
      }
    }
    return tiles;
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
            ? L.t('Showing what\'s next first. The order follows the clock.',
                'קודם מה שהכי קרוב עכשיו. הסדר הולך לפי השעון.')
            : L.t('Showing the whole day, morning to night.',
                'רואים את כל היום, מהבוקר עד הלילה.'))));
  }

  /// One more part of this routine handled — quiet micro-win. When the last
  /// part lands, the normal gentle "Is it done?" takes over.
  Future<void> _advanceStep(Routine r) async {
    final todayStr = _todayKey;
    final done =
        await IsarService.advanceStep(r.id, todayStr, r.steps.length);
    await _refreshDoneToday();
    if (done >= r.steps.length && mounted) {
      await _toggleComplete(r); // asks "Is it done?" — the person decides
    }
  }

  Future<void> _loadUserAdapt() async {
    final s = await IsarService.getSettings();
    final mad = await IsarService.isMadModeActive();
    if (mounted) {
      setState(() {
        _userType = s.userType;
        _madActive = mad;
        _guidedMode = s.guidedMode;
        _rolloverHour = s.dayRolloverHour;
      });
      // Reassurance, never alarm: every change was already saved as it
      // happened, so an ungentle close costs nothing. Say so once.
      if (!IsarService.lastExitWasClean && !_uncleanExitNoticeShown) {
        _uncleanExitNoticeShown = true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(L.t(
              'Last time didn\'t close gently — no worries. Everything was already saved as you went. Nothing lost.',
              'בפעם הקודמת האפליקציה לא נסגרה בעדינות — לא נורא. הכול נשמר תוך כדי, שום דבר לא הלך לאיבוד.')),
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
    IsarService.dataRevision.removeListener(_onDataRevision);
    _revisionDebounce?.cancel();
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
            ? L.t('Mad mode on. Say anything — it burns out by itself.',
                'מצב כעס פועל. תגידו הכול — זה נשרף מעצמו.')
            : L.t('Welcome back. Nothing you said is held against you.',
                'ברוכים השבים. שום דבר שאמרתם לא נזקף נגדכם.')),
      ),
    );
  }

  /// Complete the next unfinished routine (used by FAB and the mark_done keybind).
  Future<void> _markNextDone() async {
    final today = _logicalToday;
    final todayStr = _todayKey;
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
        SnackBar(
            content: Text(L.t('Everything for today is already done. Amazing!',
                'כל מה שהיה להיום כבר נעשה. מדהים!'))),
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
        _openDidntHappenSheet(_todayRoutines[_kbSelected]);
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

  /// The checkbox, with a gentle guard in BOTH directions (owner,
  /// 2026-07-08): a stray tap shouldn't fake a win, and a real ✓ must be
  /// takeable-back. Unchecking removes the log entirely — the day just has
  /// no answer again, it never secretly becomes a "skip".
  Future<void> _toggleComplete(Routine r) async {
    final todayStr = _todayKey;
    final isDone = await _isDoneToday(r.id, todayStr);
    if (!mounted) return;

    if (!isDone) {
      // Consent over notes (owner, 2026-07-08): if the person wrote about a
      // problem with this one, checking done must show it — the note STAYS
      // kept either way; accepting done just stops today's reminding.
      final allCaptures = await IsarService.getAllCaptures();
      final problemNote = allCaptures
          .where((c) =>
              c.linkedRoutineId == r.id &&
              c.tags.contains('need-help') &&
              c.deletedAt == null)
          .fold<QuickCapture?>(
              null, (best, c) => best == null || c.at.isAfter(best.at) ? c : best);
      if (!mounted) return;

      final noteWords = problemNote?.text ?? problemNote?.contextNote ?? '';
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(r.title),
          content: problemNote == null
              ? Text(L.t('Is it done? 🌿', 'זה נעשה? 🌿'))
              : Text(L.t(
                  'You wrote about this one:\n\n'
                      '“$noteWords”\n\n'
                      'The note stays kept either way. Done anyway?',
                  'כתבת על המשימה הזאת:\n\n'
                      '“$noteWords”\n\n'
                      'הפתק נשאר שמור בכל מקרה. לסמן שנעשה בכל זאת?')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Not yet', 'עוד לא'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(problemNote == null
                    ? L.t('Done ✓', 'נעשה ✓')
                    : L.t('Yes — done, keep the note ✓',
                        'כן — נעשה, והפתק נשאר ✓'))),
          ],
        ),
      );
      if (sure != true) return;
      await IsarService.logCompletion(
        routineId: r.id,
        date: todayStr,
        status: CompletionStatus.done,
      );
      final settings = await IsarService.getSettings();
      if (!settings.quietMode) {
        _confetti.play();
      }
    } else {
      final takeBack = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(r.title),
          content: Text(L.t('Take the ✓ back? That happens — no harm.',
              'להוריד את ה-✓? קורה — שום נזק.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Keep it done', 'להשאיר שנעשה'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Take it back', 'להוריד את הסימון'))),
          ],
        ),
      );
      if (takeBack != true) return;
      await IsarService.removeCompletion(routineId: r.id, date: todayStr);
    }

    // Refresh
    ref.invalidate(routinesProvider);
    await _refreshDoneToday();

    // Update Android widget (gadget) with fresh data
    AndroidBnsWidget.updateWidget();

    // The ✓ appearing (+ confetti unless quiet) IS the celebration.
    // No snackbar, no follow-up question — words live behind long-press.
  }

  Future<bool> _isDoneToday(String routineId, String date) async {
    final logs = await IsarService.getLogsForDate(date);
    return logs.any(
        (l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  /// Long-press = "it didn't happen" (owner, 2026-07-08). The checkbox is
  /// for done; THIS is for the problem: the person states it didn't happen
  /// and can write what got in the way — remembered, so it can get help.
  /// No Done button here; done lives on the checkbox where it belongs.
  /// Copy the newest linked note's words into today's skip record, so the
  /// why lives in the container of itself even when it was spoken on the
  /// capture screen a minute after the skip was logged.
  Future<void> _adoptReasonFromCapture(String routineId, String date) async {
    final captures = await IsarService.getAllCaptures();
    for (final c in captures) {
      // captures arrive newest-first
      if (c.linkedRoutineId != routineId) continue;
      final words = (c.text ?? c.transcript ?? c.contextNote ?? '').trim();
      if (words.isEmpty) continue;
      await IsarService.logCompletion(
        routineId: routineId,
        date: date,
        status: CompletionStatus.skipped,
        reason: words,
      );
      return;
    }
  }

  void _openDidntHappenSheet(Routine r) {
    final todayStr = _todayKey;
    final noteCtrl = TextEditingController();
    var noteSaved = false;

    // ROBUST (owner, 2026-07-08): typed words are never lost — whichever
    // way the sheet closes (button, Close, tapping outside), a non-empty
    // note saves exactly once.
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
        contextNote: L.t('What got in the way of: ${r.title}',
            'מה הפריע ל: ${r.title}'),
      ));
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 40 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(L.t(
                'Didn\'t happen? That\'s okay. If something got in the way, '
                    'write it down — it will be remembered, so it can get help.',
                'לא קרה? זה בסדר גמור. אם משהו הפריע, אפשר לכתוב אותו כאן — '
                    'הוא ייזכר, כדי שיהיה אפשר לעזור.')),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: InputDecoration(
                hintText: L.t(
                    'What got in the way? (tap the mic to speak)',
                    'מה הפריע? (הקשה על המיקרופון כדי לדבר)'),
                border: const OutlineInputBorder(),
                // STT on every comment (wave 12): long-press is level 4's
                // main problem door — typing alone is not enough.
                suffixIcon: DictationMicButton(controller: noteCtrl),
              ),
            ),
            const SizedBox(height: 12),
            QuickCaptureBar(
              onTap: () async {
                // The skip is logged BEFORE wandering into capture — the
                // "didn't happen" must never depend on finishing a note.
                await saveProblemNote();
                await IsarService.logCompletion(
                  routineId: r.id,
                  date: todayStr,
                  status: CompletionStatus.skipped,
                  reason: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (!mounted) return;
                await context.push('/capture', extra: {
                  'linkedRoutineId': r.id,
                  'tags': ['need-help'],
                });
                // The words said INSIDE capture belong to the skip too
                // (owner, 2026-07-26: the reason came back empty because it
                // was written before the person had spoken). Re-read the
                // newest linked note and put its words in the record.
                await _adoptReasonFromCapture(r.id, todayStr);
                ref.invalidate(routinesProvider);
                await _refreshDoneToday();
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                await saveProblemNote();
                if (ctx.mounted) Navigator.pop(ctx);
                // The why lives IN the skip record itself (owner,
                // 2026-07-26: "written in the container of itself") — not
                // only in a linked note that might wander or be deleted.
                await IsarService.logCompletion(
                  routineId: r.id,
                  date: todayStr,
                  status: CompletionStatus.skipped,
                  reason: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                );
                ref.invalidate(routinesProvider);
                await _refreshDoneToday();
              },
              child: Text(L.t('It didn\'t happen today', 'זה לא קרה היום')),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L.t('Close', 'סגירה')),
              ),
            ),
          ],
        ),
      ),
      // However the sheet closes, typed words are kept.
    ).whenComplete(saveProblemNote);
  }

  /// A plan's checkbox — the same gentle guard in both directions as a
  /// routine's: a stray tap must not fake a win, a real ✓ stays takeable-back.
  Future<void> _togglePlanDone(CalendarEvent plan) async {
    if (!plan.isDone) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(plan.title),
          content: Text(L.t('Is it done? 🌿', 'זה נעשה? 🌿')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Not yet', 'עוד לא'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Done ✓', 'נעשה ✓'))),
          ],
        ),
      );
      if (sure != true) return;
      await IsarService.answerEvent(plan.id, 'done');
      final settings = await IsarService.getSettings();
      if (!settings.quietMode) _confetti.play();
    } else {
      final takeBack = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(plan.title),
          content: Text(L.t('Take the ✓ back? That happens — no harm.',
              'להוריד את ה-✓? קורה — שום נזק.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Keep it done', 'להשאיר שנעשה'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Take it back', 'להוריד את הסימון'))),
          ],
        ),
      );
      if (takeBack != true) return;
      await IsarService.answerEvent(plan.id, null);
    }
    await _refreshDoneToday();
    AndroidBnsWidget.updateWidget();
  }

  /// Long-press on a plan = "it didn't happen" — same kind door as
  /// routines: state it, optionally say what got in the way, kept forever.
  void _openPlanDidntHappenSheet(CalendarEvent plan) {
    final noteCtrl = TextEditingController(text: plan.answerReason ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 40 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(L.t(
                'Didn\'t happen? That\'s okay — plans move. If something got '
                    'in the way, write it down so it can get help.',
                'לא קרה? זה בסדר — תוכניות זזות. אם משהו הפריע, אפשר לכתוב '
                    'אותו כאן כדי שיהיה אפשר לעזור.')),
            const SizedBox(height: 16),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: InputDecoration(
                hintText: L.t('What got in the way? (tap the mic to speak)',
                    'מה הפריע? (הקשה על המיקרופון כדי לדבר)'),
                border: const OutlineInputBorder(),
                suffixIcon: DictationMicButton(controller: noteCtrl),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (ctx.mounted) Navigator.pop(ctx);
                await IsarService.answerEvent(plan.id, 'skipped',
                    reason: noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim());
                await _refreshDoneToday();
              },
              child: Text(L.t('It didn\'t happen', 'זה לא קרה')),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L.t('Close', 'סגירה')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A one-time thing lands in today without touching routines (owner,
  /// 2026-08-09: "a doctor appointment and a plan I have for today").
  /// Title + optional time; the reminder follows by itself.
  Future<void> _addPlanForToday() async {
    final titleCtrl = TextEditingController();
    TimeOfDay? picked;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text(L.t('A plan for today', 'תוכנית להיום')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: L.t('What\'s the plan?', 'מה התוכנית?'),
                  hintText: L.t('e.g. Doctor at the clinic',
                      'למשל: רופא במרפאה'),
                  border: const OutlineInputBorder(),
                  suffixIcon: DictationMicButton(controller: titleCtrl),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(picked == null
                        ? L.t('Pick a time (optional)', 'לבחור שעה (רשות)')
                        : picked!.format(c)),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: c,
                          initialTime: picked ?? TimeOfDay.now());
                      if (t != null) setDlg(() => picked = t);
                    },
                  ),
                  if (picked != null)
                    TextButton(
                      onPressed: () => setDlg(() => picked = null),
                      child: Text(L.t('No time — just today',
                          'בלי שעה — פשוט היום')),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Cancel', 'ביטול'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Put it in my day', 'לשים ביום שלי'))),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    if (saved != true || title.isEmpty) return;
    final now = DateTime.now();
    await IsarService.addEvent(CalendarEvent(
      id: '',
      title: title,
      // The person's TODAY (owl time) — adding "tonight's plan" at 01:30
      // must not land it on tomorrow's list.
      date: _todayKey,
      time: picked == null
          ? null
          : '${picked!.hour.toString().padLeft(2, '0')}:'
              '${picked!.minute.toString().padLeft(2, '0')}',
      createdAt: now,
      updatedAt: now,
    ));
    await _refreshDoneToday();
    AndroidBnsWidget.updateWidget();
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
      contextNote: L.t('Daily interactive diary - goals & wins',
          'יומן יומי — מטרות והצלחות'),
    );
    await IsarService.addCapture(capture);
    _diaryController.clear();
    ref.invalidate(routinesProvider);
    AndroidBnsWidget.updateWidget();

    if (mounted) {
      // Brief and quiet — the person already chose to keep it; don't ask
      // again. (Promoting a memory to "keep forever" lives in Memories.)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L.t('In the diary. ✓', 'נשמר ביומן. ✓')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final routinesAsync = ref.watch(routinesProvider);
    final today = _logicalToday; // owl time: 01:30 is still tonight
    // On wide screens the sidebar shell already handles navigation — hide
    // the duplicate nav buttons below to keep the screen calm and focused.
    // Width decides (tablets wave, 2026-08-09): an Android tablet or iPad
    // in landscape has the sidebar too, not just PCs.
    final hasSidebar = BnsLayout.isWide(context);
    // Keyboard hints stay a PC thing — a tablet has no Ctrl to press.
    final isDesktopWide = hasSidebar &&
        (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Today • BNS', 'היום • BNS'),
        leading: Image.asset('assets/icon/bns_logo.png', height: 28, width: 28),
        centerTitle: false,
        hideOnDesktopWide:
            true, // modern PC sidebar handles navigation chrome + marked selection
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: L.t('Calendar', 'לוח שנה'),
            onPressed: () => context.push('/calendar'),
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: L.t('Sync your devices', 'סנכרון בין המכשירים'),
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.psychology),
            tooltip: L.t('Memories', 'זיכרונות'),
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
                              ? L.t(
                                  'It\'s okay to be furious. This space can take it.',
                                  'מותר להיות עצבניים. המקום הזה יכול להכיל את זה.')
                              : L.t('Hey — whatever today looks like is okay.',
                                  'היי — איך שהיום נראה, זה בסדר.'),
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
                          label: Text(L.t('I\'m mad', 'אני כועס/ת')),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _madActive
                        ? L.t(
                            'Rage is part of the marathon too. Skipping today on purpose still counts.',
                            'גם כעס הוא חלק מהמרתון. לדלג על היום בכוונה — גם זה נחשב.')
                        : L.t('Routines support you. They never get mad.',
                            'השגרות כאן בשבילך. הן אף פעם לא כועסות.'),
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
                                      L.t(
                                          'Mad mode is on. Curse everyone and everything — only you see it, and vents burn out on their own within ~2 days. Being here while angry is still showing up.',
                                          'מצב כעס פועל. אפשר לקלל את כולם ואת הכול — רק אתם רואים את זה, והפריקות נשרפות מעצמן תוך יומיים בערך. להיות כאן גם כשכועסים — זה עדיין להגיע.'),
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
                                    // Await + refresh: the vented moment
                                    // must be VISIBLE the second you're
                                    // back ("isn't creating anything that
                                    // I can see" — it was, invisibly).
                                    onPressed: () async {
                                      await context.push('/capture', extra: {
                                        'tags': ['mad-vent'],
                                      });
                                      await _refreshDoneToday();
                                    },
                                    icon: const Icon(Icons.record_voice_over),
                                    label: Text(L.t('Vent now — voice or text',
                                        'לפרוק עכשיו — בקול או בכתב')),
                                  ),
                                  TextButton(
                                    onPressed: _toggleMad,
                                    child: Text(L.t('Calm again', 'רגוע/ה שוב')),
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
                  const SizedBox(height: 20),

                  routinesAsync.when(
                    // SILK: every ✓ invalidates the provider, and a reload
                    // used to blank the whole list for a spinner before
                    // painting it again — a flash, a jump, and a lost place
                    // on every single tap. Keep showing what is already
                    // there while the new data arrives.
                    skipLoadingOnReload: true,
                    skipLoadingOnRefresh: true,
                    data: (routines) {
                      final todaysRoutines = routines
                          .where((r) => r.appliesOn(today) && r.isActive)
                          .toList();
                      // One day, one list: routines and plans woven by the
                      // same clock laws (answered sinks, order preference
                      // honored). A doctor appointment stands IN the day.
                      final dayList = weaveDayList(
                        routines: todaysRoutines,
                        plans: _todayPlans,
                        doneRoutineIds: _doneTodayIds,
                        skippedRoutineIds: _skippedTodayIds,
                        nextFirst: _nextFirstOrder,
                        now: DateTime.now(),
                        rolloverHour: _rolloverHour,
                      );
                      _todayRoutines = dayList
                          .whereType<Routine>()
                          .toList(); // for the keyboard handler

                      // Hero always uses clock "what's next" order — the
                      // list below can still follow the person's preference.
                      final openNext = openRoutinesInNextOrder(
                        todays: todaysRoutines,
                        doneIds: _doneTodayIds,
                        skippedIds: _skippedTodayIds,
                      );
                      // ALWAYS RETURN: something already started outranks
                      // the clock. Half-done work is the easiest thing in
                      // the world to lose and the hardest to come back to —
                      // so the app carries the place, not the person.
                      final started = openNext.where((r) {
                        final done = _stepProgress[r.id] ?? 0;
                        return r.steps.isNotEmpty &&
                            done > 0 &&
                            done < r.steps.length;
                      }).toList();
                      final hero = started.isNotEmpty
                          ? started.first
                          : (openNext.isNotEmpty ? openNext.first : null);
                      final resuming = started.isNotEmpty;
                      final coming = openNext
                          .where((r) => r.id != hero?.id)
                          .take(2)
                          .toList();

                      if (dayList.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DayClearCard(
                                  guided: _guidedMode, textScale: _textScale),
                              if (!_guidedMode) ...[
                                const SizedBox(height: 12),
                                FilledButton.tonalIcon(
                                  onPressed: () => context.push('/routines'),
                                  icon: const Icon(Icons.add),
                                  label: Text(L.t(
                                      'Add a routine when you\'re ready',
                                      'להוסיף שגרה כשמתאים לך')),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _addPlanForToday,
                                  icon: const Icon(Icons.event),
                                  label: Text(L.t(
                                      'Or a one-time plan for today',
                                      'או תוכנית חד-פעמית להיום')),
                                ),
                              ],
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // —— NEXT HERO (clean, big, one job) ——
                          if (hero != null)
                            NextHeroCard(
                              routine: hero,
                              textScale: _textScale,
                              resuming: resuming,
                              stepsDone: _stepProgress[hero.id] ?? 0,
                              recentNote: _recentNoteText[hero.id],
                              onDone: () => _toggleComplete(hero),
                              onProblem: () =>
                                  _openDidntHappenSheet(hero),
                              onStepDone: hero.steps.isNotEmpty
                                  ? () => _advanceStep(hero)
                                  : null,
                            )
                          else
                            DayClearCard(
                                guided: _guidedMode, textScale: _textScale),

                          if (coming.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            ComingUpStrip(
                              textScale: _textScale,
                              items: coming
                                  .map((r) => (
                                        routine: r,
                                        timeLabel: r.time,
                                      ))
                                  .toList(),
                            ),
                          ],

                          const SizedBox(height: 28),
                          Text(
                              L.t('Today\'s gentle steps',
                                  'הצעדים הרכים של היום'),
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                          if (isDesktopWide)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                L.t(
                                    'Keyboard: Ctrl+G jumps here • ↑↓ move • Enter = done • S = skip with reason',
                                    'מקלדת: Ctrl+G קופץ לכאן • ↑↓ תזוזה • Enter = נעשה • S = דילוג עם סיבה'),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                            ),
                          const SizedBox(height: 10),

                          // Focusable list: Ctrl+G reaches it, arrows move,
                          // Enter completes, S opens skip-with-reason.
                          Focus(
                            focusNode: _routinesFocus,
                            onKeyEvent: (node, event) =>
                                _handleListKey(event),
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
                                if (!_guidedMode)
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      // One-time things enter the day here
                                      // — never forced into a routine. A
                                      // real button, not 12px whisper text:
                                      // on the PC nobody FOUND it (owner
                                      // QA, 2026-08-09).
                                      FilledButton.tonalIcon(
                                        onPressed: _addPlanForToday,
                                        icon: const Icon(Icons.event, size: 18),
                                        label: Text(L.t('A plan for today',
                                            'תוכנית להיום')),
                                      ),
                                      TextButton.icon(
                                        onPressed: _toggleTodayOrder,
                                        icon: Icon(
                                            _nextFirstOrder
                                                ? Icons.schedule
                                                : Icons.wb_twilight,
                                            size: 16),
                                        label: Text(
                                            _nextFirstOrder
                                                ? L.t('List: what\'s next',
                                                    'רשימה: מה הבא בתור')
                                                : L.t(
                                                    'List: morning to night',
                                                    'רשימה: מהבוקר עד הלילה'),
                                            style: const TextStyle(
                                                fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                // Routines AND plans, woven by one clock
                                // (a plan carries the weight of a step).
                                ..._dayTiles(dayList),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Text(L.t('Error loading: $e', 'שגיאה בטעינה: $e')),
                  ),

                  const SizedBox(height: 24),

                  // Today's storms, kept — "what I got mad at this day",
                  // said sweetly and revisitable at the end of the rows, so
                  // it can be told to the right person when things are calm
                  // ("I didn't remember who tells me what").
                  if (_madToday.isNotEmpty) ...[
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.air,
                            color: Theme.of(context).colorScheme.tertiary),
                        title: Text(
                            L.t('Hard moments today, kept', 'רגעים קשים היום, שמורים')),
                        subtitle: Text(L.t(
                            '${_madToday.length} kept — to look at, hear again, '
                                'or tell someone when it suits you.',
                            '${_madToday.length} נשמרו — להסתכל, לשמוע שוב, '
                                'או לספר למישהו כשמתאים לך.')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showKeptWords(
                            L.t('Hard moments today', 'רגעים קשים היום'),
                            _madToday),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // The diary: one calm box, no presets, no double-asking.
                  // (Copy is for the person, never for the developer.)
                  // Guided mode (level 4): no building, no diary box —
                  // only the list; words go through long-press or capture.
                  if (!_guidedMode) ...[
                    Text(L.t('Diary', 'יומן'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      L.t('A good thing, a hard thing — both belong here.',
                          'דבר טוב, דבר קשה — לשניהם יש מקום כאן.'),
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
                        hintText: L.t(
                            'How is today going? (tap the mic to speak)',
                            'איך היום מרגיש? (הקשה על המיקרופון כדי לדבר)'),
                        helperText: isDesktopWide
                            ? L.t('Ctrl+D jumps here', 'Ctrl+D קופץ לכאן')
                            : null,
                        border: const OutlineInputBorder(),
                        // Massive diary spine: voice into the diary box,
                        // not type-only (wave 12).
                        suffixIcon:
                            DictationMicButton(controller: _diaryController),
                      ),
                    ),
                    const SizedBox(height: 4),
                    ElevatedButton.icon(
                      onPressed: _saveDiaryEntry,
                      icon: const Icon(Icons.check),
                      label: Text(L.t('Keep in diary', 'לשמור ביומן')),
                    ),
                  ],

                  const SizedBox(height: 24),
                  QuickCaptureBar(
                    onTap: () async {
                      await context.push('/capture');
                      await _refreshDoneToday();
                    },
                  ),
                  // Day diary thread — the spine of "everything said and done".
                  // Available in guided mode too (read path); building stays elsewhere.
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/day'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(L.t(
                        'Today\'s words — everything said and done',
                        'מילות היום — כל מה שנאמר ונעשה')),
                  ),
                  // When the sidebar is on screen (PC or a wide tablet) it
                  // covers navigation — these stay for phones.
                  // Guided mode: the calendar stays (visual, read-mostly);
                  // managing routines is the inspector's job, not shown here.
                  if (!hasSidebar) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/calendar'),
                      icon: const Icon(Icons.event_note),
                      label: Text(L.t(
                          'Open calendar for appointments & day notes',
                          'לפתוח לוח שנה — תורים והערות ליום')),
                    ),
                    const SizedBox(height: 8),
                    if (!_guidedMode)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/routines'),
                      icon: const Icon(Icons.list_alt),
                      label: Text(L.t('Manage all routines (add, edit, delete)',
                          'ניהול כל השגרות (הוספה, עריכה, מחיקה)')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/memories'),
                      icon: const Icon(Icons.psychology),
                      label: Text(L.t(
                          'Memory section: Remember & Memorize what happened',
                          'אזור הזיכרון: לזכור ולשנן את מה שקרה')),
                    ),
                  ],

                  // Caregiver door (level 4): the day can be set up right
                  // HERE, on this device — nothing relies on the P2P sync
                  // existing or working. A tap only explains; opening takes
                  // a deliberate long hold, so a wandering finger never
                  // lands in setup by accident.
                  if (_guidedMode) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(L.t(
                                'This button is for the caregiver. '
                                    'Hold it a moment and the setup opens.',
                                'הכפתור הזה מיועד למלווה. '
                                    'לחיצה ארוכה — וההגדרות נפתחות.'))));
                      },
                      onLongPress: () => context
                          .push('/routines', extra: {'caregiver': true}),
                      icon: const Icon(Icons.volunteer_activism),
                      label: Text(L.t('Caregiver — hold to set up the day',
                          'מלווה — לחיצה ארוכה לסידור היום')),
                    ),
                  ],

                  // TODAY NEVER HIDES ITSELF (owner's phone, 2026-07-26):
                  // the floating ✓ button used to sit ON the last button
                  // (Memory section) — unreadable, untappable. The list now
                  // ends with clear air taller than the button, so every
                  // last control scrolls fully past it.
                  const SizedBox(height: 100),
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
      // Shorter words on the floating button (owner's phone, 2026-07-26):
      // the long label made a WIDE pill that sat on top of the last row.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _markNextDone,
        label: Text(L.t('Mark next ✓', 'לסמן את הבא ✓')),
        icon: const Icon(Icons.check_rounded),
      ),
    );
  }
}
