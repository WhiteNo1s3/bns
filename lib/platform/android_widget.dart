import 'package:home_widget/home_widget.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:intl/intl.dart';

/// Android Home Widget (Gadget) for BNS.
/// Shows gentle summary: routines due today, last sync, quick capture action.
/// 
/// Perfect, low cognitive: large tap targets, positive text.
/// Update on data changes (complete routine, sync).
/// 
/// Note: Requires full flutter build after adding widget provider in Android (home_widget does some auto).
/// iOS high-profile: home_widget can extend to iOS home screen widgets too (today's mission etc.).
/// For icon: use the perfect happy green smiling brain we configured (bns_icon.png).

class AndroidBnsWidget {
  static const _widgetName = 'BnsHomeWidget';
  static const _androidWidgetName = 'BnsHomeWidgetProvider';

  /// Update the widget with current data.
  /// Shows:
  /// - Today's mission (due routines today)
  /// - Plans for next N days (configurable, default 2 to avoid stress)
  /// - Positive encouragement, recent memory if any
  /// Call after routine complete, capture, sync, etc.
  static Future<void> updateWidget() async {
    try {
      final settings = await IsarService.getSettings();
      final allRoutines = await IsarService.getAllRoutines();
      final forwardDays = settings.widgetForwardDays.clamp(0, 14); // cap to avoid stress

      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      // Today's mission: routines that apply today
      final todayRoutines = allRoutines.where((r) => r.isActive && r.appliesOn(today)).toList();
      final todayMissions = todayRoutines.map((r) => r.title).join(' • ');

      // Completed today
      final logsToday = await IsarService.getLogsForDate(todayStr);
      final completedToday = logsToday.where((l) => l.status == CompletionStatus.done).length;

      // Upcoming plans: calendar events in next forwardDays
      String upcoming = '';
      if (forwardDays > 0) {
        final upcomingEvents = <String>[];
        for (int d = 1; d <= forwardDays; d++) {
          final futureDate = today.add(Duration(days: d));
          final dateStr = DateFormat('yyyy-MM-dd').format(futureDate);
          final events = await IsarService.getEventsForDate(dateStr);
          if (events.isNotEmpty) {
            final dayLabel = DateFormat('E').format(futureDate);
            upcomingEvents.add('$dayLabel: ${events.map((e) => e.title).join(", ")}');
          }
        }
        upcoming = upcomingEvents.join(' | ');
      }

      // Recent memory (last non-quick for story)
      final recentMemories = await IsarService.getAllCaptures();
      final lastMem = recentMemories.firstWhere(
        (c) => c.memoryLevel != MemoryLevel.quick,
        orElse: () => QuickCapture(id: '', at: DateTime.now(), memoryLevel: MemoryLevel.quick),
      );
      final recentStory = lastMem.contextNote ?? lastMem.text ?? '';

      await HomeWidget.saveWidgetData<String>('device_name', settings.deviceName);
      await HomeWidget.saveWidgetData<String>('today_mission', todayMissions.isEmpty ? 'No missions today - rest is ok' : todayMissions);
      await HomeWidget.saveWidgetData<int>('completed_today', completedToday);
      await HomeWidget.saveWidgetData<String>('upcoming', upcoming.isEmpty ? 'No plans ahead (as set)' : upcoming);
      await HomeWidget.saveWidgetData<String>('recent_memory', recentStory.isEmpty ? 'You\'ve done great things before' : recentStory);
      await HomeWidget.saveWidgetData<String>('last_sync', settings.lastFullSyncAt?.toIso8601String() ?? 'Never');

      // Positive encouragement - user gets power, motivated, away from past
      final summary = 'You showed up. $completedToday done today. Small steps = big wins. You got this!';
      await HomeWidget.saveWidgetData<String>('summary', summary);

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
    } catch (e) {
      // Fail silent, widget is bonus
    }
  }

  /// Handle widget click (e.g. quick capture or open app)
  static Future<void> handleWidgetClick(String? widgetId, String? data) async {
    // In full, use to open specific.
    // For now, app opens via main.
  }
}