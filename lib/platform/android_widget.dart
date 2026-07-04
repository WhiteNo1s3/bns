import 'package:home_widget/home_widget.dart';
import 'package:bns/data/local/isar_service.dart';

/// Android Home Widget (Gadget) for BNS.
/// Shows gentle summary: routines due today, last sync, quick capture action.
/// 
/// Perfect, low cognitive: large tap targets, positive text.
/// Update on data changes (complete routine, sync).
/// 
/// Note: Requires full flutter build after adding widget provider in Android (home_widget does some auto).
/// For icon: use the perfect app icon we configured.

class AndroidBnsWidget {
  static const _widgetName = 'BnsHomeWidget';
  static const _androidWidgetName = 'BnsHomeWidgetProvider';

  /// Update the widget with current data.
  /// Call after routine complete, capture, sync, etc.
  static Future<void> updateWidget() async {
    try {
      final settings = await IsarService.getSettings();
      final routines = await IsarService.getAllRoutines();
      // Simple: count active routines (in real filter today's)
      final activeCount = routines.where((r) => r.isActive).length;

      final today = DateTime.now();
      final dateStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final logs = await IsarService.getLogsForDate(dateStr);
      final completedToday = logs.where((l) => l.status == CompletionStatus.done).length;

      await HomeWidget.saveWidgetData<String>('device_name', settings.deviceName);
      await HomeWidget.saveWidgetData<int>('active_routines', activeCount);
      await HomeWidget.saveWidgetData<int>('completed_today', completedToday);
      await HomeWidget.saveWidgetData<String>('last_sync', settings.lastFullSyncAt?.toIso8601String() ?? 'Never');

      // Gentle positive text
      await HomeWidget.saveWidgetData<String>('summary', 'You showed up today. $completedToday done.');

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