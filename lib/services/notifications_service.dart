import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int32List;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/reminder_plan.dart';
import 'package:bns/core/wake_words.dart';
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
    // THE WAKE ANSWERS IN ONE PRESS (owner, 2026-08-19: "there is no way
    // to shut down the alarm... no other screen than accept or snooze").
    if (actionId == 'wake_up') {
      await stopWakeRing();
      onOpen?.call('/');
      return;
    }
    if (actionId == 'wake_snooze') {
      await snoozeWake();
      onOpen?.call('/');
      return;
    }
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
        await _zonedScheduleExactish(
          p.id,
          p.title,
          p.body,
          tz.TZDateTime.from(p.firstAt, tz.local),
          _detailsFor(settings, p),
          mode: AndroidScheduleMode.exactAllowWhileIdle,
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

    try {
      await _scheduleWake(settings, routines, events, now);
    } catch (_) {
      // The wake failing to schedule must never break the reminders.
    }
    _lastFingerprint = fingerprint;
  }

  /// EXACT DELIVERY (owner as user, 2026-08-18: "I don't get the
  /// notifications"). Inexact alarms were the silent killer — Samsung
  /// batches and defers them until they help nobody. Reminders ride
  /// exact-while-idle now (the manifest carries USE_EXACT_ALARM — BNS is
  /// an alarm-and-calendar app in the most literal sense); if a device
  /// still refuses exact alarms, the reminder arrives inexactly rather
  /// than not at all.
  static Future<void> _zonedScheduleExactish(
    int id,
    String title,
    String body,
    tz.TZDateTime at,
    NotificationDetails details, {
    required AndroidScheduleMode mode,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    } catch (_) {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        at,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
    }
  }

  // ---- THE WAKE ALARM ----
  // Owner as user, 2026-08-18: "I need an alarm clock... many days have
  // nothing to wake up for and I do have." A real alarm — alarm channel,
  // alarm sound, full screen, insistent — and the ring CARRIES THE
  // REASON: the day's opening, rebuilt fresh on every reschedule. The
  // phone's own clock app can hold a second copy (planted from the
  // Tomorrow room) — that one carries the person's songs and survives
  // anything; this one carries the meaning.

  static const int _wakeId = 910777;

  /// A pressed snooze: the ring returns once at this moment, then the
  /// daily wake resumes. In-memory only — the scheduled alarm itself
  /// survives process death; this merely keeps a foreground
  /// rescheduleAll from wiping the pending return.
  static DateTime? _wakeSnoozeUntil;

  /// Kill the ringing now (the insistent loop dies with the
  /// notification) and re-arm tomorrow's wake.
  static Future<void> stopWakeRing() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_wakeId);
    } catch (_) {}
    _wakeSnoozeUntil = null;
    await rescheduleAll(force: true);
  }

  /// "עוד 10 דקות" — the ring comes back once, soon.
  static Future<void> snoozeWake({int minutes = 10}) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_wakeId);
    } catch (_) {}
    _wakeSnoozeUntil = DateTime.now().add(Duration(minutes: minutes));
    await rescheduleAll(force: true);
  }

  static Future<void> _scheduleWake(AppSettings settings,
      List<Routine> routines, List<CalendarEvent> events, DateTime now) async {
    // A Care seat's store may carry the person's wake — it rings on THEIR
    // nightstand, never on the helper's (the seat wears the helper's hat).
    if (settings.caregiverDevice) return;
    final parsed = parseHhmm(settings.wakeAlarmTime);
    if (parsed == null || !settings.notificationsEnabled) return;

    // A live snooze wins the slot: one return ring, then daily again.
    final snooze = _wakeSnoozeUntil;
    if (snooze != null && snooze.isAfter(now)) {
      final note = settings.wakeAlarmNote.trim();
      final body = note.isNotEmpty
          ? note
          : wakeBodyFor(
              routines: routines,
              events: events,
              day: logicalDateOf(snooze, settings.dayRolloverHour),
              rolloverHour: settings.dayRolloverHour,
              t: L.t,
            );
      await _zonedScheduleExactish(
        _wakeId,
        L.t('Good morning', 'בוקר טוב'),
        body,
        tz.TZDateTime.from(snooze, tz.local),
        _wakeDetails(settings, body),
        mode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: null, // once — the daily returns after
        payload: 'wake',
      );
      return;
    }
    _wakeSnoozeUntil = null;

    var fireAt = DateTime(
        now.year, now.month, now.day, parsed.hour, parsed.minute);
    if (!fireAt.isAfter(now)) fireAt = fireAt.add(const Duration(days: 1));

    // The ring opens the day it lands on — the body is that day's plan.
    final note = settings.wakeAlarmNote.trim();
    final body = note.isNotEmpty
        ? note
        : wakeBodyFor(
            routines: routines,
            events: events,
            day: logicalDateOf(fireAt, settings.dayRolloverHour),
            rolloverHour: settings.dayRolloverHour,
            t: L.t,
          );

    await _zonedScheduleExactish(
      _wakeId,
      L.t('Good morning', 'בוקר טוב'),
      body,
      tz.TZDateTime.from(fireAt, tz.local),
      _wakeDetails(settings, body),
      // The strongest scheduling Android has: the OS treats it as an
      // alarm clock (status-bar alarm icon, immune to Doze).
      mode: AndroidScheduleMode.alarmClock,
      matchDateTimeComponents: DateTimeComponents.time, // every day
      payload: 'wake',
    );
  }

  static NotificationDetails _wakeDetails(AppSettings settings, String body) {
    final android = AndroidNotificationDetails(
      'bns_wake',
      L.t('Wake alarm', 'השכמה'),
      channelDescription: L.t('The morning alarm that carries your day',
          'השכמת הבוקר שנושאת את היום שלך'),
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      // The phone's own alarm tone — the one the person already chose
      // and knows. Ring like an alarm, through the alarm stream.
      sound: const UriAndroidNotificationSound(
          'content://settings/system/alarm_alert'),
      audioAttributesUsage: AudioAttributesUsage.alarm,
      // FLAG_INSISTENT: the sound holds until the person answers it —
      // a wake that gives up after four seconds wakes nobody.
      additionalFlags: Int32List.fromList(const [4]),
      color: BnsTheme.reminderColor(settings),
      styleInformation: BigTextStyleInformation(body),
      // Exactly two answers, right on the ring (owner, 2026-08-19:
      // "no other screen than accept or snooze, thats it").
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('wake_up', L.t('I\'m up ✓', 'קמתי ✓'),
            showsUserInterface: true),
        AndroidNotificationAction(
            'wake_snooze', L.t('10 more minutes', 'עוד 10 דקות'),
            showsUserInterface: true),
      ],
    );

    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    return NotificationDetails(android: android, iOS: darwin, macOS: darwin);
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
