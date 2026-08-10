import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/theme.dart';

/// Windows reminders, in-app: flutter_local_notifications has no Windows
/// side, so while the app is open a gentle card appears at the moment a
/// timed routine or plan arrives — in the person's chosen reminder color,
/// with a soft way in and no way to fail. Other platforms keep their real
/// system notifications and never see this.
class DesktopReminderService {
  DesktopReminderService._();

  /// Global messenger so the reminder card can appear from any screen.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static Timer? _timer;
  static void Function(String route)? _onOpen;

  /// Fired keys ('yyyy-MM-dd|r|id' / 'yyyy-MM-dd|e|id') so one moment
  /// reminds once. In-memory on purpose: a restart may re-offer a reminder
  /// that is still inside its little window — kinder than losing it.
  static final Set<String> _fired = {};

  /// A reminder is shown only within this window after its moment — the
  /// app waking up at night must not replay the whole missed day.
  static const Duration _window = Duration(minutes: 3);

  static void start({void Function(String route)? onOpen}) {
    if (!Platform.isWindows || _timer != null) return;
    _onOpen = onOpen;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _tick().catchError((_) {});
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _tick() async {
    final settings = await IsarService.getSettings();
    if (!settings.notificationsEnabled || settings.caregiverDevice) return;

    final now = DateTime.now();
    // OWL TIME: which day "today" is follows the person's border — at
    // 01:30 with a 04:00 border, the 02:00 pills are TONIGHT's, and their
    // answered-state lives under tonight's date.
    final rollover = settings.dayRolloverHour;
    final todayStr = logicalDayKey(now, rollover);
    final logicalDay = logicalDateOf(now, rollover);

    // Routines due right now, still unanswered today.
    final logs = await IsarService.getLogsForDate(todayStr);
    final answered = logs.map((l) => l.routineId).toSet();
    final routines = await IsarService.getAllRoutines();
    for (final r in routines) {
      if (!r.appliesOn(logicalDay) || r.time == null) continue;
      if (answered.contains(r.id)) continue;
      final at = _timeOn(now, r.time!);
      if (at == null || !_inWindow(now, at)) continue;
      final key = '$todayStr|r|${r.id}';
      if (!_fired.add(key)) continue;
      _show(
        settings,
        L.t('${r.title} — whenever you\'re ready',
            '${r.title} — מתי שנוח לך'),
        route: '/',
      );
    }

    // Plans with a time: one heads-up, the chosen lead before.
    final lead = settings.eventReminderMinutes;
    if (lead < 0) return;
    final events = await IsarService.getAllEvents();
    for (final e in events) {
      if (e.isAllDay || e.time == null || e.isAnswered) continue;
      final date = DateTime.tryParse(e.date);
      if (date == null) continue;
      final hm = e.time!.split(':');
      final h = int.tryParse(hm[0]);
      final m = hm.length > 1 ? int.tryParse(hm[1]) : null;
      if (h == null || m == null) continue;
      // A small-hour plan belongs to that date's NIGHT (owl time).
      final at = actualMomentOf(date, h, m, rollover);
      final remindAt = at.subtract(Duration(minutes: lead));
      if (!_inWindow(now, remindAt)) continue;
      final key = '${e.date}|e|${e.id}';
      if (!_fired.add(key)) continue;
      _show(
        settings,
        L.t('${e.title} — at ${e.time}. No rush, just so it doesn\'t slip away.',
            '${e.title} — בשעה ${e.time}. בלי לחץ, רק כדי שזה לא יברח.'),
        route: '/day?date=${e.date}',
      );
    }
  }

  static bool _inWindow(DateTime now, DateTime at) =>
      !now.isBefore(at) && now.isBefore(at.add(_window));

  static DateTime? _timeOn(DateTime day, String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static void _show(AppSettings settings, String text,
      {required String route}) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final color = BnsTheme.reminderColor(settings);
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 20),
      behavior: SnackBarBehavior.floating,
      // The person's color carries the reminder; words stay high-contrast.
      backgroundColor: Color.alphaBlend(color.withValues(alpha: 0.25),
          const Color(0xFF1F2933)),
      content: Row(
        children: [
          Icon(Icons.notifications_none, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
      action: SnackBarAction(
        label: L.t('Open', 'פתיחה'),
        textColor: color,
        onPressed: () => _onOpen?.call(route),
      ),
    ));
  }
}
