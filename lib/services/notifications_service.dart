import 'dart:io' show Platform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:flutter/material.dart';
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
      'bns_routines',
      'Gentle Reminders',
      channelDescription: 'Kind reminders for your routines',
      importance: Importance.low,
      priority: Priority.low,
      styleInformation: const BigTextStyleInformation(
        'Take your time. This is just a gentle nudge.',
      ),
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      routine.id.hashCode, // stable id
      'Gentle reminder',
      '${routine.title} — whenever you\'re ready',
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
    final routines = await IsarService.getAllRoutines();
    for (final r in routines.where((r) => r.isActive && r.time != null)) {
      await scheduleRoutineReminder(r);
    }
    final settings = await IsarService.getSettings();
    if (settings.listReadyNudgeEnabled && settings.notificationsEnabled) {
      await scheduleListReadyNudge();
    }
  }

  /// Soft presence: the "folder on the desk" — your list is here.
  /// Never shaming; never "you missed us." Low priority, once a day ~10:00.
  static Future<void> scheduleListReadyNudge() async {
    if (!_initialized || !_supported) return;
    const id = 77001;
    await _plugin.cancel(id);

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 10, 0);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final androidDetails = AndroidNotificationDetails(
      'bns_presence',
      'Gentle presence',
      channelDescription: 'A soft note that your list is here',
      importance: Importance.low,
      priority: Priority.low,
      styleInformation: const BigTextStyleInformation(
        'Whenever you are ready. No rush.',
      ),
    );

    await _plugin.zonedSchedule(
      id,
      'Your list is ready 🌿',
      'Whenever you are ready. No rush.',
      scheduled,
      NotificationDetails(android: androidDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'presence:list-ready',
    );
  }
}
