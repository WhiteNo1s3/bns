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
import 'package:bns/ui/widgets/gather_sheet.dart';
import 'package:bns/ui/widgets/postpone_sheet.dart';
import 'package:bns/ui/widgets/bns_menu_screen.dart';
import 'package:bns/ui/widgets/next_hero_card.dart';
import 'package:bns/ui/widgets/quick_capture_bar.dart';
import 'package:bns/ui/widgets/kept_memories_strip.dart';
import 'package:bns/core/day_feed.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/care_lock.dart';
import 'package:bns/core/didnt_happen.dart';
import 'package:bns/core/pairing_prompt.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/bns_desktop_shell.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/features/calendar/calendar_screen.dart';
import 'package:bns/features/calendar/day_view.dart';
import 'package:bns/features/sync/sync_screen.dart';
import 'package:bns/features/routines/routines_screen.dart';
import 'package:bns/features/memory/memories_screen.dart';
import 'package:bns/features/diary/day_thread_screen.dart';
import 'package:bns/features/caregiver/caregiver_home_screen.dart';
import 'package:home_widget/home_widget.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/care_profiles.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/sync/lan_sync_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/desktop_reminder_service.dart';
import 'package:bns/services/haptics.dart';
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
  // The isolation door opens BEFORE anything can touch a store: a
  // --data-dir / BNS_DATA_DIR instance is pinned to its own home and can
  // never write the live one (synchronous, so even the first frame's
  // providers read the pinned home).
  BnsHome.applyStartupArgs(args);
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
      // Turning haptics off in Settings takes effect on the very next
      // touch, not the next launch.
      BnsHaptics.refresh();
      // The containment state follows the settings, always — the router
      // asks it synchronously on every navigation.
      IsarService.getSettings().then((s) {
        // guided && !caregiver: a helper's copy is never the guided one,
        // even in the moment before a contaminated store heals on load.
        CareState.guided.value = s.guidedMode && !s.caregiverDevice;
        CareState.caregiver.value = s.caregiverDevice;
      }).catchError((Object _) {});
    };
    // The hand gets its answer from the first gesture onward.
    await BnsHaptics.init();
    final startupSettings = await IsarService.getSettings();
    CareState.guided.value =
        startupSettings.guidedMode && !startupSettings.caregiverDevice;
    CareState.caregiver.value = startupSettings.caregiverDevice;
    // CARE PROFILES (docs/care-profiles.md): a pre-profile seat's one
    // person becomes the first named door by themselves, and the
    // remembered sitting reopens — BEFORE sync starts serving, so the
    // first answer already comes from the right store.
    if (startupSettings.caregiverDevice) {
      try {
        final migrated = await CareProfiles.migrateLegacyIfNeeded();
        if (migrated != null) {
          // The person just moved behind their new door — the seat sits
          // straight down with them, or the first open looks emptied.
          await CareProfiles.enter(migrated);
        } else {
          await CareProfiles.resumeSitting();
        }
      } catch (_) {}
    }
    await NotificationsService.init();
    // First sweep also clears anything stale left in the shade from before
    // this launch — opening BNS means the day on screen takes over.
    await NotificationsService.onAppInFront();
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
    //
    // But not on top of בוצע, and never for a friend already in the file
    // (level-1 note, 2026-08-17: "חלון חיבור במק נשאר אחרי שבן פון כבר
    // מהימן"; "דף צימוד לא על בוצע"). A trusted device stays quiet — deaf
    // sync is not a reason to re-pair; a mid-answer person finishes their
    // answer first; a leftover extra copy cannot stack a second sheet.
    LanSyncService.instance.onPairRequest = (req) async {
      final trusted = await IsarService.getTrustedDevice(req.deviceId);
      final disposition = pairAskDisposition(
        alreadyTrusted: trusted != null,
        completing: PairingGate.instance.isCompleting,
        promptAlreadyOpen: PairingGate.instance.isPrompting,
      );
      if (disposition == PairAskDisposition.stayQuiet) return null;
      if (disposition == PairAskDisposition.waitForDone) {
        await PairingGate.instance.waitUntilIdle();
      }
      return PairingGate.instance.runPrompt(() async {
        final ctx = _router.routerDelegate.navigatorKey.currentContext;
        if (ctx == null) return null;
        return showEnterCodeDialog(context: ctx, peerName: req.deviceName);
      });
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
      // PROBLEMS SPEAK, SUCCESS STAYS QUIET (owner, 2026-08-16: "the sync
      // success shouldn't make toast all the time, it is annoying").
      // Auto-sync doing its job is ambient — Today's last-synced line and
      // the Sync screen carry it. A toast is for something that needs you.
      if (p.error == null) return;
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
  // LEVEL 4 IS CONTAINED AT THE DOOR FRAME, not by hiding doorknobs
  // (level-4 tester, 2026-08-16, walked out through the menu, the bottom
  // doors, keyboard shortcuts and the caregiver screen). Whatever opens a
  // route — a button someone forgot to hide, a keybind, a deep link — it
  // passes through here, and here there is one rule: a guided device
  // shows the day and the telling door; the caregiver's rooms open inside
  // their unlocked sitting; everything else goes home.
  // The decision itself lives beside CareState (one truth, testable):
  // a guided device shows the day and the telling door, an unlocked
  // caregiver sitting opens their rooms — and a HELPER's device is never
  // contained at all, whatever a contaminated store still claims.
  redirect: (context, state) => CareState.containmentRedirect(state.uri.path),
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
        // Query params carry the same keys for string-only doors (a shade
        // action's deep link has no `extra` to ride on); extra wins.
        final q = state.uri.queryParameters;
        final qTags = (q['tags'] ?? '')
            .split(',')
            .where((t) => t.trim().isNotEmpty)
            .toList();
        final screen = QuickCaptureScreen(
          linkedRoutineId:
              extra['linkedRoutineId'] as String? ?? q['linkedRoutineId'],
          initialText: extra['initialText'] as String?,
          initialTags: (extra['tags'] as List?)?.cast<String>() ??
              (qTags.isEmpty ? null : qTags),
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
    GoRoute(
      path: '/menu',
      // The phone's whole map, in words — pops in place (static law).
      builder: (context, state) =>
          _wrapForDesktop(context, const BnsMenuScreen(), state.uri.toString()),
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
          // The day on screen carries the plan now: stale reminders leave
          // the shade, upcoming ones re-register fresh (throttled inside).
          NotificationsService.onAppInFront();
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
        // A widget-press is a NEW visit — the reused screen resets (and
        // banks any leftover words) instead of resuming last time's box.
        QuickCaptureScreen.askFresh({'autoRecord': true});
        _router.go('/capture', extra: {'autoRecord': true});
      case 'add-memory':
        QuickCaptureScreen.askFresh();
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
        palette: RelaxingPalette.clay,
        mode: ThemeModeSetting.system,
      ),
      darkTheme: BnsTheme.build(
        palette: RelaxingPalette.clay,
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

    // LEVEL 4 ON A PC: the keyboard was a corridor out of the list
    // (level-4 tester, 2026-08-16: "all keyboard shortcuts are still
    // on — sync, routines, memories"). In guided mode only the day's own
    // keys survive: mark the next one, go home, tell something.
    const guidedKeys = {'mark_done', 'open_today', 'quick_capture'};
    final guided = settings?.guidedMode ?? false;

    final shortcuts = <ShortcutActivator, Intent>{};
    binds.forEach((id, combo) {
      if (enabled[id] == false) return;
      if (guided && !guidedKeys.contains(id)) return;
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
      QuickCaptureScreen.askFresh();
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
  // The last few kept thoughts — so a recording waits on Today, visible,
  // instead of feeling like it went nowhere.
  List<QuickCapture> _recentKept = const [];
  // Today's PLANS — one-time things (a doctor appointment, an errand) that
  // stand in the day with the weight of a step (owner, 2026-08-09).
  List<CalendarEvent> _todayPlans = const [];
  Map<String, int> _stepProgress = const {}; // routineId → parts done today
  // routineId → when the person said to knock again ("later, by my will").
  Map<String, DateTime> _snoozedUntil = const {};
  bool _nextFirstOrder = false; // false = morning→night (default)
  bool _guidedMode = false; // level 4: only the list, inspector builds
  String? _lastSyncLine; // cached "last synced" note (no per-frame queries)
  // OWL TIME: the hour the person's day ends (0 = midnight). Everything
  // "today" on this screen goes through these two, so a 02:00 pill at
  // 01:30 still belongs to TONIGHT's list for a person with a 04:00 border.
  int _rolloverHour = 0;
  // When the person-day begins (later-today offers slots from here on).
  int _dayStartHour = 0;

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
    _dayStartHour = settings.dayStartHour;
    final todayStr = _todayKey;
    final logs = await IsarService.getLogsForDate(todayStr);
    final trusted = await IsarService.getTrustedDevices();
    final steps = await IsarService.stepProgressForDate(todayStr);
    final todayPlans = await IsarService.getEventsForDate(todayStr);
    // The person's own "later"s — the hero honors them, the tiles say them.
    final snoozes = await IsarService.getReminderSnoozes();
    final snoozedRoutines = <String, DateTime>{};
    snoozes.forEach((payload, until) {
      final parts = payload.split(':');
      if (parts.length >= 2 && parts[0] == 'routine') {
        snoozedRoutines[parts[1]] = until;
      }
    });
    // The kept "why"s: need-help notes from the last few days, latest one
    // per routine. They ride the tiles so the reason is met, not searched.
    final captures = await IsarService.getAllCaptures();
    final noteText = <String, String>{};
    final noteWhen = <String, String>{};
    final latestAt = <String, DateTime>{};
    for (final c in captures) {
      // TODAY only. Last week's "why" pinned to today's tile mixed the
      // days together and read like the app holding the past against the
      // person — older notes live in the day diary and in Memories.
      if (!belongsToLogicalDay(c.at, todayStr, _rolloverHour)) continue;
      final rid = c.linkedRoutineId;
      if (rid == null || !c.tags.contains('need-help')) continue;
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
    for (final c in captures) {
      if (!belongsToLogicalDay(c.at, todayStr, _rolloverHour)) continue;
      final rid = c.linkedRoutineId;
      if (rid != null) (kept[rid] ??= []).add(c);
      if (c.tags.contains('mad-vent')) mad.add(c);
    }
    // The newest kept thoughts, for the strip that proves nothing vanished.
    final recentKept = visibleMemories(captures).take(3).toList();
    if (!mounted) return;
    setState(() {
      _recentKept = recentKept;
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
      _snoozedUntil = snoozedRoutines;
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
            snoozedUntil: _snoozedUntil[r.id],
            recentNote: _recentNoteText[r.id],
            recentNoteWhen: _recentNoteWhen[r.id],
            keptCount: _keptByRoutine[r.id]?.length ?? 0,
            onShowKept: () =>
                _showKeptWords(r.title, _keptByRoutine[r.id] ?? const []),
            onToggle: () => _toggleComplete(r),
            onSkip: () => _openDidntHappenSheet(r),
            // Later today: hidden in guided mode — there the inspector
            // moves the clock, and the person's list simply follows.
            onLaterToday: (_guidedMode || r.time == null)
                ? null
                : (hhmm) => _postponeItem(r, hhmm),
            rolloverHour: _rolloverHour,
            startHour: _dayStartHour,
            dayKey: _todayKey,
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
            onGather: () => _openGather(item),
            onLaterToday: (_guidedMode || item.time == null || item.isAllDay)
                ? null
                : (hhmm) => _postponeItem(item, hhmm),
            rolloverHour: _rolloverHour,
            startHour: _dayStartHour,
          ),
        ));
      }
    }
    return tiles;
  }

  /// LATER TODAY — still this day, a later clock (tester, 2026-08-16: "a
  /// late morning is normal"). A routine keeps its usual time and gets a
  /// one-day override; a plan simply moves (that visit is only today).
  /// Not a skip, not an edit of tomorrow.
  Future<void> _postponeItem(Object item, String hhmm) async {
    if (item is Routine) {
      await IsarService.addRoutine(item.postponeOn(_todayKey, hhmm));
    } else if (item is CalendarEvent) {
      await IsarService.addEvent(
          item.copyWith(time: hhmm, updatedAt: DateTime.now()));
    }
    await NotificationsService.rescheduleAll();
    await _refreshDoneToday();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t('Moved to $hhmm — still today.',
            'עבר ל־$hhmm — עדיין היום.'))));
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
        _dayStartHour = s.dayStartHour;
      });
      // Reassurance, never alarm: every change was already saved as it
      // happened, so an ungentle close costs nothing. Say so once.
      if (!IsarService.lastExitWasClean && !_uncleanExitNoticeShown) {
        _uncleanExitNoticeShown = true;
        // ADULT WARMTH (owner + his father, 2026-08-16: "we went baby
        // soft... it's for adults"): state the fact, skip the cooing.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(L.t(
              'Everything from last time is saved.',
              'הכול מהפעם הקודמת שמור.')),
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

      // DONE IS A QUIET ✓ (owner law 2026-07-08; the level-1 note and the
      // cross-tree pass, 2026-08-17: "בוצע = וי. נשארים בהיום. אף אחד לא
      // שואל שוב."). The tap marks it — no second question. The ONE ask
      // that stays is consent-over-notes: when the person wrote about a
      // problem with this very routine, done must show them their own
      // words first (that is their voice, not a re-ask).
      if (problemNote != null) {
        final noteWords = problemNote.text ?? problemNote.contextNote ?? '';
        final sure = await PairingGate.instance.run(() => showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(r.title),
                content: Text(L.t(
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
                      child: Text(L.t('Yes — done, keep the note ✓',
                          'כן — נעשה, והפתק נשאר ✓'))),
                ],
              ),
            ));
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
    } else {
      final takeBack = await PairingGate.instance.run(() => showDialog<bool>(
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
          ));
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
    // One of the sheet's own doors answered (skip / postpone / capture) —
    // a dismiss after that must not write a second answer.
    var resolved = false;

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

    // While this door is open the person is mid-answer — a pairing ask
    // waits its turn (level-1 note, 2026-08-17: "דף צימוד לא על בוצע").
    PairingGate.instance.begin();
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
                'Didn\'t happen. If something got in the way, write it — '
                    'it\'s kept.',
                'לא קרה. אם משהו הפריע, אפשר לכתוב — זה נשמר.')),
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
            // LATER, BY MY WILL (owner, 2026-08-16, for levels 3–4): the
            // third kind answer. Not done, not skipped — just "not right
            // now", said with two big taps and a filling bar.
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showPostponeSheet(
                    context: ctx, title: r.title, big: _guidedMode);
                if (d == null) return;
                resolved = true; // postponed is an answer — not a skip
                await saveProblemNote();
                await IsarService.snoozeReminder(
                    'routine:${r.id}', DateTime.now().add(d));
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshDoneToday();
              },
              style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(_guidedMode ? 60 : 52)),
              icon: const Icon(Icons.update, size: 24),
              label: Text(L.t('Later — remind me again',
                  'מאוחר יותר — להזכיר שוב')),
            ),
            const SizedBox(height: 12),
            QuickCaptureBar(
              onTap: () async {
                // The skip is logged BEFORE wandering into capture — the
                // "didn't happen" must never depend on finishing a note.
                resolved = true;
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
                resolved = true;
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
      // However the sheet closes, typed words are kept — and words on a
      // closing sheet ARE the answer (level-1 note, 2026-08-17: "כתבתי
      // למה לא קרה. סגירה. זה נשאר על הפריט. לא מסך שני."): a dismiss
      // with words logs the skip itself, unless a door already answered
      // or today already holds an answer for this routine.
    ).whenComplete(() async {
      PairingGate.instance.end();
      await saveProblemNote();
      final dismissal = didntHappenOnDismiss(noteCtrl.text);
      if (resolved || !dismissal.skipped) return;
      final logs = await IsarService.getLogsForDate(todayStr);
      if (logs.any((l) => l.routineId == r.id)) return;
      await IsarService.logCompletion(
        routineId: r.id,
        date: todayStr,
        status: CompletionStatus.skipped,
        reason: dismissal.reason,
      );
      ref.invalidate(routinesProvider);
      await _refreshDoneToday();
    });
  }

  /// A plan's checkbox — done is a QUIET ✓ (owner law; level-1 note,
  /// 2026-08-17: "אף אחד לא שואל שוב"). Only taking a kept answer back
  /// still asks: a stray tap must not silently erase a real ✓.
  Future<void> _togglePlanDone(CalendarEvent plan) async {
    if (!plan.isDone) {
      await IsarService.answerEvent(plan.id, 'done');
      final settings = await IsarService.getSettings();
      if (!settings.quietMode) _confetti.play();
    } else {
      final takeBack = await PairingGate.instance.run(() => showDialog<bool>(
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
          ));
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
                'Plans move. If something got in the way, write it — '
                    'it\'s kept.',
                'תוכניות זזות. אם משהו הפריע, אפשר לכתוב — זה נשמר.')),
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
            const SizedBox(height: 12),
            // A plan can also simply move — same third answer as routines.
            OutlinedButton.icon(
              onPressed: () async {
                final d = await showPostponeSheet(
                    context: ctx, title: plan.title, big: _guidedMode);
                if (d == null) return;
                await IsarService.snoozeReminder(
                    'event:${plan.id}:${plan.date}', DateTime.now().add(d));
                if (ctx.mounted) Navigator.pop(ctx);
                await _refreshDoneToday();
              },
              style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(_guidedMode ? 60 : 52)),
              icon: const Icon(Icons.update, size: 24),
              label: Text(L.t('Later — remind me again',
                  'מאוחר יותר — להזכיר שוב')),
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

  /// "What do we take?" — opened from a plan on the day.
  ///
  /// ANSWERING IS OPEN TO EVERYONE, including level 4 (owner, 2026-08-15,
  /// from Shiba: the person who cannot gather a thing is still asked, and
  /// the asking is what keeps them a participant instead of a bystander).
  /// Only BUILDING the list is the helper's, in guided mode.
  Future<void> _openGather(CalendarEvent plan) async {
    await showGatherSheet(
      context: context,
      plan: plan,
      canEdit: !_guidedMode,
      onChanged: (items) async {
        await IsarService.addEvent(
            plan.copyWith(gather: items, updatedAt: DateTime.now()));
        await _refreshDoneToday();
        AndroidBnsWidget.updateWidget();
      },
    );
  }

  /// "MADE IT" IS EVERYONE'S (owner, 2026-08-16: "level 4 is not disabled
  /// from this feature — it's not a list for the caregiver only"). The
  /// person keeps their own day — the auto-summary of what was done, said
  /// and met — and because it is a capture like any other, it travels to
  /// the caregiver by the same sync as everything else. Level 4 lost this
  /// door when the containment closed DayView; it lives on Today now.
  Future<void> _memorizeToday() async {
    final todayStr = _todayKey;
    final routines = await IsarService.getAllRoutines();
    final applicable = routines
        .where((r) => r.appliesOn(_logicalToday) && r.isActive)
        .toList();
    final logs = await IsarService.getLogsForDate(todayStr);
    final captures = await IsarService.getCapturesForDate(_logicalToday);
    final events = await IsarService.getEventsForDate(todayStr);
    final summary = buildDayAutoSummary(
      date: _logicalToday,
      applicableRoutines: applicable,
      logs: logs,
      captures: captures,
      events: events,
      t: L.t,
      dayLabel: DateFormat.yMMMd(L.isHebrew ? 'he' : 'en')
          .format(_logicalToday),
    );
    await IsarService.addCapture(QuickCapture(
      id: '',
      at: DateTime.now(),
      text: summary,
      tags: const ['day-memory', 'auto-summary'],
      memoryLevel: MemoryLevel.memorize,
      isDayMemory: true,
    ));
    await _refreshDoneToday();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('The day is kept.', 'היום נשמר.'))));
    }
  }

  /// TOMORROW, SET UP TONIGHT (owner, 2026-08-15: "planning tomorrow the
  /// night before so I wake into a ready day"). Waking with no idea what
  /// the day holds is the thing that costs a whole morning — and the
  /// evening is when there is calm to decide. This opens tomorrow itself,
  /// where plans and their gather lists are built in advance.
  Future<void> _planTomorrow() async {
    final tomorrow = _logicalToday.add(const Duration(days: 1));
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DayView(date: tomorrow)),
    );
    await _refreshDoneToday();
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
    // The diary line joins "What you kept" immediately — written, then
    // seen, with nothing in between.
    await _refreshDoneToday();
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
        // ONE MAP (owner, 2026-08-16): the sidebar is the map on wide
        // screens, doors+menu are the map on phones — the top bar carries
        // NO third copy of any room. The lone exception is guided mode,
        // where doors and menu are deliberately absent: the caregiver's
        // key-gated Settings door lives here, or nowhere.
        actions: _guidedMode
            ? [
                TextButton.icon(
                  // The same key opens it; a device with no key yet offers
                  // the caregiver the setup instead of swinging open.
                  onPressed: () async {
                    final ok = await showCareUnlockDialog(context,
                        offerSetupIfMissing: true);
                    if (!ok || !mounted) return;
                    context.push('/sync');
                  },
                  icon: const Icon(Icons.settings_outlined, size: 22),
                  label: Text(L.t('Settings', 'הגדרות')),
                ),
              ]
            : const [],
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
                  // HONEST STORAGE (the "void" fix, owner QA 2026-08-14):
                  // if the disk is refusing writes, the person hears it here
                  // — calmly, with a hand to hold — instead of losing words
                  // to a silent failure. Gone the moment a write lands.
                  ValueListenableBuilder<String?>(
                    valueListenable: IsarService.saveTrouble,
                    builder: (context, trouble, _) {
                      if (trouble == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          color:
                              Theme.of(context).colorScheme.tertiaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(trouble,
                                    style: TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer)),
                                const SizedBox(height: 4),
                                Text(
                                    L.t(
                                        'If this keeps up, a new home for BNS '
                                            'can be chosen on the Sync screen.',
                                        'אם זה נמשך, אפשר לבחור ל־BNS בית חדש '
                                            'במסך הסנכרון.'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer)),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: TextButton(
                                    onPressed: IsarService.flush,
                                    child: Text(L.t('Try again now',
                                        'לנסות שוב עכשיו')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          _madActive
                              ? L.t('Furious is allowed here.',
                                  'מותר לכעוס כאן.')
                              : L.t('Your day.', 'היום שלך.'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 22 * _textScale),
                        ),
                      ),
                      // Level 4 gets the list, not a control panel
                      // (tester, 2026-08-16: "Today is not only a list.
                      // Many words. 'I am angry.' Extra buttons"). Rage
                      // still has its door — the long-press telling flow —
                      // without a standing button to decode.
                      if (!_madActive && !_guidedMode)
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
                        ? L.t('Deciding to skip today counts too.',
                            'גם להחליט לדלג היום — נחשב.')
                        : L.t('What gets done, gets done. The rest waits.',
                            'מה שנעשה — נעשה. השאר יחכה.'),
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
                  // Level 4: fewer words — the machinery line stays out.
                  if (_lastSyncLine != null && !_guidedMode)
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
                      // same clock laws. THE DAY STAYS STEADY (owner,
                      // 2026-08-14): a ✓ or a "didn't happen" shows in
                      // place — tiles never jump. A doctor appointment
                      // stands IN the day.
                      final dayList = weaveDayList(
                        routines: todaysRoutines,
                        plans: _todayPlans,
                        doneRoutineIds: _doneTodayIds,
                        skippedRoutineIds: _skippedTodayIds,
                        nextFirst: _nextFirstOrder,
                        now: DateTime.now(),
                        rolloverHour: _rolloverHour,
                        startHour: _dayStartHour,
                      );
                      // LATE WAKE-UPS ARE WELCOME (owner QA, 2026-08-14:
                      // "I woke up today at 15:30... I had no clue what to
                      // do"). Count timed things from earlier that are
                      // still open — the card below meets the person with
                      // orientation, never with a scoreboard of misses.
                      final nowMinutes =
                          owlNowMinutes(DateTime.now(), _rolloverHour);
                      var openFromEarlier = 0;
                      for (final item in dayList) {
                        String? t;
                        if (item is Routine) {
                          if (_doneTodayIds.contains(item.id) ||
                              _skippedTodayIds.contains(item.id)) {
                            continue;
                          }
                          t = item.time;
                        } else if (item is CalendarEvent) {
                          if (item.isAnswered || item.isAllDay) continue;
                          t = item.time;
                        }
                        if (t == null || !t.contains(':')) continue;
                        final hp = t.split(':');
                        final m = owlMinutesOf(int.tryParse(hp[0]) ?? 0,
                            int.tryParse(hp[1]) ?? 0, _rolloverHour);
                        // Half an hour of grace: "just now" isn't "earlier".
                        if (m + 30 < nowMinutes) openFromEarlier++;
                      }
                      _todayRoutines = dayList
                          .whereType<Routine>()
                          .toList(); // for the keyboard handler

                      // Hero walks the person-day from now — not the
                      // next clock time that already passed this morning.
                      // The list below can still follow the person's order.
                      final openNext = openRoutinesInNextOrder(
                        todays: todaysRoutines,
                        doneIds: _doneTodayIds,
                        skippedIds: _skippedTodayIds,
                        snoozedIds: _snoozedUntil.keys.toSet(),
                        now: DateTime.now(),
                        dayKey: _todayKey,
                        rolloverHour: _rolloverHour,
                        startHour: _dayStartHour,
                      );
                      // ALWAYS RETURN: something already started outranks
                      // the clock — unless it is a leftover morning stack.
                      // Half-done work is the easiest thing in the world
                      // to lose; a 21:45 morning leftover must not come
                      // back on top while evening is still open.
                      final nowForNext = DateTime.now();
                      final started = openNext.where((r) {
                        final done = _stepProgress[r.id] ?? 0;
                        if (r.steps.isEmpty ||
                            done <= 0 ||
                            done >= r.steps.length) {
                          return false;
                        }
                        return !isNextMorningSlot(
                          usualHhmm: r.time,
                          todayHhmm: r.timeOn(_todayKey),
                          now: nowForNext,
                          startHour: _dayStartHour,
                          rolloverHour: _rolloverHour,
                        );
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
                          // Waking mid-day: one warm line of orientation.
                          // Earlier things are OPEN, not missed — late is
                          // fully fine, and saying "didn't happen" counts.
                          if (openFromEarlier >= 2) ...[
                            Card(
                              color: Theme.of(context)
                                  .colorScheme
                                  .secondaryContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  L.t(
                                      'A few earlier things are still open. '
                                          'Late still counts. Start anywhere.',
                                      'כמה דברים מוקדמים עדיין פתוחים. '
                                          'מאוחר — עדיין נחשב. אפשר להתחיל '
                                          'מכל מקום.'),
                                  style: TextStyle(
                                      fontSize: 14 * _textScale,
                                      height: 1.35,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSecondaryContainer),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
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
                              onLaterToday:
                                  (_guidedMode || hero.time == null)
                                      ? null
                                      : (hhmm) => _postponeItem(hero, hhmm),
                              rolloverHour: _rolloverHour,
                              startHour: _dayStartHour,
                              dayKey: _todayKey,
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

                                // TOMORROW IS DECIDED TONIGHT. Waking with
                                // no idea what the day holds costs the
                                // whole morning (owner, 2026-08-15: "I woke
                                // up today at 15:30... I had no clue what to
                                // do"). The evening is when there is calm to
                                // choose — and what gets set up here is
                                // waiting, already answered-for, on waking.
                                if (!_guidedMode) ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: _planTomorrow,
                                    icon: const Icon(Icons.bedtime_outlined,
                                        size: 20),
                                    style: OutlinedButton.styleFrom(
                                        minimumSize:
                                            const Size.fromHeight(52)),
                                    label: Text(L.t(
                                        'Set up tomorrow, while it\'s calm',
                                        'לסדר את מחר, כשרגוע')),
                                  ),
                                ],
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

                  // WHAT YOU KEPT — the proof that a recording went
                  // somewhere. A thought saved and then invisible is the
                  // same as a thought lost (owner QA, 2026-08-14: "I give
                  // text and voices to the void").
                  if (_recentKept.isNotEmpty && !_guidedMode) ...[
                    KeptMemoriesStrip(memories: _recentKept),
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

                  // ONE MAP (owner, 2026-08-16, after the level-1 tester's
                  // "old 4-tab still there = two maps"): the doors hold the
                  // main rooms, the menu holds the rest, and Today carries
                  // NO second copy of either. Every button that used to
                  // stand here — capture, day words, manage routines — was
                  // a duplicate door to a room that already has one.
                  //
                  // The one exception is guided mode, where doors and menu
                  // are deliberately absent: this bar IS the telling door.
                  if (_guidedMode) ...[
                    const SizedBox(height: 24),
                    QuickCaptureBar(
                      onTap: () async {
                        await context.push('/capture');
                        await _refreshDoneToday();
                      },
                    ),
                    const SizedBox(height: 12),
                    // "Made it" belongs to level 4 too — one tap keeps the
                    // day, and it reaches the caregiver with the sync.
                    OutlinedButton.icon(
                      onPressed: _memorizeToday,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(60)),
                      icon: const Icon(Icons.stars, size: 26),
                      label: Text(L.t('Keep this day', 'לשמור את היום'),
                          style: TextStyle(fontSize: 16 * _textScale)),
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
                      // The old tap-hint TAUGHT the way in ("hold it a
                      // moment and the setup opens" — the level-4 tester
                      // followed it straight to Trash/Add/Edit). A tap now
                      // says only whose door this is; the caregiver knows
                      // their own hold, and the key does the guarding —
                      // with the setup offered when no key exists yet.
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(L.t(
                                'This door belongs to the caregiver. '
                                    'Your day is all here. 💚',
                                'הדלת הזאת של המלווה. '
                                    'היום שלך נמצא כולו כאן. 💚'))));
                      },
                      onLongPress: () async {
                        if (!await showCareUnlockDialog(context,
                            offerSetupIfMissing: true)) return;
                        if (!mounted) return;
                        await context
                            .push('/routines', extra: {'caregiver': true});
                      },
                      icon: const Icon(Icons.volunteer_activism),
                      label: Text(L.t('For the caregiver', 'למלווה')),
                    ),
                  ],

                  // TODAY NEVER HIDES ITSELF (owner's phone, 2026-07-26;
                  // again from the level-4 tester, 2026-08-16: "a list
                  // opened over the Save button — hard to press"). The
                  // list ends with clear air TALLER than the floating
                  // button, so every last control scrolls fully past it.
                  const SizedBox(height: 148),
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
