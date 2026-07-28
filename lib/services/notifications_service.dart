import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';

/// Polite, gentle notification service.
/// Only reminds for time-based routines. Never shaming.
class NotificationsService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// flutter_local_notifications has no Windows implementation —
  /// everything here quietly no-ops there instead of crashing.
  static bool get _supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isLinux;

  static Future<void> init() async {
    if (_initialized || !_supported) return;

    tzdata.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(android: android, iOS: ios);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        // Could navigate to Today when tapped
        debugPrint('Notification tapped: ${resp.payload}');
      },
    );

    // Request permissions on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Schedule a gentle reminder for a routine that has a time.
  static Future<void> scheduleRoutineReminder(Routine routine) async {
    if (!_initialized || routine.time == null) return;

    await cancelRoutineReminder(routine.id);

    final parts = routine.time!.split(':');
    final hour = int.tryParse(parts[0]) ?? 9;
    final minute = int.tryParse(parts[1]) ?? 0;

    // Schedule daily at the routine time (local)
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      'bns_routines', // channel id stays English — it is an identifier
      L.t('Gentle Reminders', 'תזכורות עדינות'),
      channelDescription: L.t('Kind reminders for your routines',
          'תזכורות נחמדות לשגרות שלך'),
      importance: Importance.low,
      priority: Priority.low,
      styleInformation: BigTextStyleInformation(
        L.t('Take your time. This is just a gentle nudge.',
            'אין לחץ, בקצב שלך. זו רק תזכורת עדינה.'),
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      routine.id.hashCode, // stable id
      L.t('Gentle reminder', 'תזכורת עדינה'),
      L.t('${routine.title} — whenever you\'re ready',
          '${routine.title} — מתי שנוח לך'),
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
      payload: 'routine:${routine.id}',
    );
  }

  static Future<void> cancelRoutineReminder(String routineId) async {
    if (!_initialized) return;
    await _plugin.cancel(routineId.hashCode);
  }

  /// Cancel all (used for settings toggle)
  static Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Reschedule all active time-based routines (call on app start or after changes)
  static Future<void> rescheduleAll() async {
    if (!_initialized) return;
    await cancelAll();
    // A CAREGIVER IS NOT THE PATIENT (owner, 2026-07-27). Their device
    // carries the other person's day so they can build and watch it — it
    // must never buzz them at 07:00 to take pills that are not theirs.
    final settings = await IsarService.getSettings();
    if (settings.caregiverDevice) return;
    final routines = await IsarService.getAllRoutines();
    for (final r in routines.where((r) => r.isActive && r.time != null)) {
      await scheduleRoutineReminder(r);
    }
  }
}
