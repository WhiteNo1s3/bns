import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/reminder_plan.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/ui/theme.dart';

/// Polite, gentle notification service.
/// Reminds for time-based routines and for plans on the calendar.
/// The person chooses how loud (quiet / gentle / bright) and in what color.
/// Never shaming — a reminder is an open hand, not a tap on the shoulder.
class NotificationsService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String _lastFingerprint = '';
  static Timer? _debounce;

  /// Set from main: where a tapped reminder navigates ('/', '/day?date=…').
  static void Function(String route)? onOpen;

  /// flutter_local_notifications has no Windows implementation —
  /// everything here quietly no-ops there instead of crashing.
  /// (On Windows the in-app DesktopReminderService carries reminders.)
  static bool get _supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  static Future<void> init() async {
    if (_initialized || !_supported) return;

    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');

    // macOS and Linux each need their own settings block — without them
    // initialize() throws and reminders silently die on those platforms.
    const initSettings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) =>
          _handleResponse(resp.payload, resp.actionId),
    );

    // Request permissions on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;

    // App opened by tapping a reminder while it was closed: land where the
    // reminder points (Today, or the day of the plan).
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _handleResponse(launch!.notificationResponse?.payload,
            launch.notificationResponse?.actionId);
      }
    } catch (_) {}
  }

  /// A reminder was touched. The two shade buttons answer RIGHT THERE —
  /// "waking up to a pile I cannot press I-did-them on ruins the flow"
  /// (owner QA, 2026-08-14). Both open the app (same isolate — the store
  /// stays single-writer); a plain tap just lands where the reminder points.
  static Future<void> _handleResponse(String? payload, String? actionId) async {
    if (actionId == 'bns_later') {
      // "Later, I said so" (owner, 2026-08-15): the task moves by the
      // person's will — two hours, nothing marked, no judgment. The
      // reminder simply keeps their word and knocks again.
      if (payload != null) {
        await IsarService.snoozeReminder(
            payload, DateTime.now().add(const Duration(hours: 2)));
        await rescheduleAll(force: true);
      }
      onOpen?.call('/');
      return;
    }
    if (actionId == 'bns_done') {
      await _answerFromShade(payload, done: true);
      onOpen?.call(routeForReminderPayload(payload));
      return;
    }
    if (actionId == 'bns_why') {
      // Saying "didn't happen" is a decision — a win. The skip is logged
      // and the kind door opens for the why (voice first), exactly like
      // the in-app sheet. Closing without a word is always allowed.
      await _answerFromShade(payload, done: false);
      onOpen?.call(whyRouteForReminderPayload(payload));
      return;
    }
    onOpen?.call(routeForReminderPayload(payload));
  }

  /// Apply a shade answer to the store (done, or a deliberate "didn't
  /// happen"). Failures fall through quietly — the app is opening anyway,
  /// and the same answer is one tap away inside.
  static Future<void> _answerFromShade(String? payload,
      {required bool done}) async {
    try {
      if (payload == null) return;
      final parts = payload.split(':');
      if (parts.length >= 2 && parts[0] == 'routine') {
        final settings = await IsarService.getSettings();
        await IsarService.logCompletion(
          routineId: parts[1],
          date: logicalDayKey(DateTime.now(), settings.dayRolloverHour),
          status: done ? CompletionStatus.done : CompletionStatus.skipped,
        );
      } else if (parts.length >= 2 && parts[0] == 'event') {
        await IsarService.answerEvent(parts[1], done ? 'done' : 'skipped');
      }
      AndroidBnsWidget.updateWidget();
    } catch (_) {}
  }

  static DateTime _lastShadeSweep = DateTime.fromMillisecondsSinceEpoch(0);

  /// The app is in front — the day on screen carries the plan now, so
  /// reminders that already fired leave the shade and everything still
  /// coming is re-registered fresh. This is what turns "waking up to
  /// 1000000 things" into opening the app and simply seeing today.
  /// Throttled: front-flips are frequent, alarm re-registration isn't free.
  static Future<void> onAppInFront() async {
    if (!_initialized) return;
    final now = DateTime.now();
    if (now.difference(_lastShadeSweep) < const Duration(minutes: 3)) return;
    _lastShadeSweep = now;
    await rescheduleAll(force: true);
  }

  /// Cancel all (used for settings toggle)
  static Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
    _lastFingerprint = '';
  }

  /// Data changed somewhere (a tap, an edit, a sync, an import) — reschedule
  /// soon if the change touched anything reminders depend on. Debounced so a
  /// burst of writes costs one pass; the fingerprint makes no-op passes free.
  static void maybeRescheduleSoon() {
    if (!_initialized) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      rescheduleAll();
    });
  }

  /// Reschedule everything from the current data (call on app start or after
  /// changes). Skips silently when nothing reminders care about has changed.
  static Future<void> rescheduleAll({bool force = false}) async {
    if (!_initialized) return;
    final settings = await IsarService.getSettings();
    final routines = await IsarService.getAllRoutines();
    final events = await IsarService.getAllEvents();
    final snoozes = await IsarService.getReminderSnoozes();
    final now = DateTime.now();

    final fingerprint = reminderFingerprint(
        routines: routines,
        events: events,
        settings: settings,
        now: now,
        snoozes: snoozes);
    if (!force && fingerprint == _lastFingerprint) return;

    final plan = planReminders(
        routines: routines,
        events: events,
        settings: settings,
        now: now,
        snoozes: snoozes);

    await _plugin.cancelAll();
    await _cleanupUnusedChannels(settings);

    for (final p in plan) {
      try {
        await _plugin.zonedSchedule(
          p.id,
          p.title,
          p.body,
          tz.TZDateTime.from(p.firstAt, tz.local),
          _detailsFor(settings, p),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: switch (p.repeat) {
            PlannedRepeat.daily => DateTimeComponents.time,
            PlannedRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
            PlannedRepeat.none => null,
          },
          payload: p.payload,
        );
      } catch (_) {
        // One bad reminder must never take down the rest.
      }
    }
    _lastFingerprint = fingerprint;
  }

  // ---- How a reminder looks and sounds: the person's choice ----

  /// Android channels are frozen at creation, so each style is its own
  /// channel — switching style simply schedules into a different one.
  static String _channelIdFor(String style) => switch (style) {
        'quiet' => 'bns_reminders_soft',
        'bright' => 'bns_reminders_bright',
        _ => 'bns_reminders_gentle',
      };

  /// The old single channel (pre-styles) plus whichever style channels are
  /// not in use — removed so system settings show exactly one clean entry.
  static Future<void> _cleanupUnusedChannels(AppSettings settings) async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return;
    final keep = _channelIdFor(settings.reminderStyle);
    for (final id in [
      'bns_routines', // legacy channel from before the styles existed
      'bns_reminders_soft',
      'bns_reminders_gentle',
      'bns_reminders_bright',
    ]) {
      if (id == keep) continue;
      try {
        await androidImpl.deleteNotificationChannel(id);
      } catch (_) {}
    }
  }

  static NotificationDetails _detailsFor(
      AppSettings settings, PlannedReminder p) {
    final style = settings.reminderStyle;
    final color = BnsTheme.reminderColor(settings);

    final android = AndroidNotificationDetails(
      _channelIdFor(style),
      L.t('Gentle reminders', 'תזכורות עדינות'),
      channelDescription: L.t('Kind reminders for your routines and plans',
          'תזכורות נחמדות לשגרות ולתוכניות שלך'),
      importance: switch (style) {
        'quiet' => Importance.low,
        'bright' => Importance.high,
        _ => Importance.defaultImportance,
      },
      priority: switch (style) {
        'quiet' => Priority.low,
        'bright' => Priority.high,
        _ => Priority.defaultPriority,
      },
      playSound: style != 'quiet',
      // The color the person chose — the small accent that says "this one
      // is mine" at a glance, before any reading.
      color: color,
      styleInformation: BigTextStyleInformation(
        '${p.body}\n${L.t('Take your time. This is just a gentle nudge.', 'אין לחץ, בקצב שלך. זו רק תזכורת עדינה.')}',
      ),
      // A reminder nobody touched bows out by itself after a while (the
      // person chooses how long) — waking hours later must not mean a
      // pile of stale nudges (owner QA, 2026-08-14). 0 = stays until seen.
      timeoutAfter: settings.reminderTimeoutMinutes > 0
          ? Duration(minutes: settings.reminderTimeoutMinutes).inMilliseconds
          : null,
      // Answers live ON the reminder: the quiet ✓, and the kind door for
      // "didn't happen". Both open the app (single writer, no isolates).
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('bns_done', L.t('Done ✓', 'נעשה ✓'),
            showsUserInterface: true),
        AndroidNotificationAction(
            'bns_later', L.t('In 2 hours', 'בעוד שעתיים'),
            showsUserInterface: true),
        AndroidNotificationAction(
            'bns_why', L.t('Didn\'t happen', 'לא קרה'),
            showsUserInterface: true),
      ],
    );

    final darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: style != 'quiet',
      presentBadge: false,
      interruptionLevel: style == 'quiet'
          ? InterruptionLevel.passive
          : InterruptionLevel.active,
    );

    final linux = LinuxNotificationDetails(
      urgency: style == 'quiet'
          ? LinuxNotificationUrgency.low
          : LinuxNotificationUrgency.normal,
    );

    return NotificationDetails(
        android: android, iOS: darwin, macOS: darwin, linux: linux);
  }
}
