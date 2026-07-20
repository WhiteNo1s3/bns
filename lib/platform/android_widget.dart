import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:intl/intl.dart';

/// Android home-screen widget BUNDLE (the 2026-07-06 Android pivot).
///
/// Three widgets, all dirt simple, all huge targets, all kind:
/// - **Today** (`BnsTodayWidgetProvider`): today's mission + gentle progress.
/// - **Coming up** (`BnsUpcomingWidgetProvider`): plans for the next N days
///   (user-configurable, default 2 — nobody needs more stress than 2 days)
///   plus one recent memory ("part of the story, since we forget what
///   we've done when building").
/// - **Quick actions** (`BnsActionsWidgetProvider`): three big buttons —
///   + Task, + Memory, 🎤 Voice. The 🎤 button opens the app ALREADY
///   recording: one tap from home screen to talking.
///
/// Native side: android/app/src/main/kotlin/com/whiteno1se/bns/*.kt,
/// layouts + provider configs in android/app/src/main/res/.
/// Call [updateWidget] after anything that changes what they show
/// (routine done, capture, sync, import).
class AndroidBnsWidget {
  static const _providers = [
    'BnsTodayWidgetProvider',
    'BnsUpcomingWidgetProvider',
    'BnsActionsWidgetProvider',
  ];

  static Future<void> updateWidget() async {
    if (!Platform.isAndroid) return;
    try {
      final settings = await IsarService.getSettings();
      final allRoutines = await IsarService.getAllRoutines();
      final forwardDays =
          settings.widgetForwardDays.clamp(0, 14); // cap to avoid stress

      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);

      // Today's mission: specials first (out of ordinary), then routines.
      // Widget = the "folder on the desk" — rediscovery without remembering the app.
      final todayRoutines =
          allRoutines.where((r) => r.isActive && r.appliesOn(today)).toList();
      final specials =
          await IsarService.getSpecialOrdersForDate(todayStr);
      final logsToday = await IsarService.getLogsForDate(todayStr);
      final handledIds = logsToday.map((l) => l.routineId).toSet();
      final doneCount =
          logsToday.where((l) => l.status == CompletionStatus.done).length;

      final openRoutines =
          todayRoutines.where((r) => !handledIds.contains(r.id)).toList();
      String nextHero = '';
      if (specials.isNotEmpty) {
        nextHero = '📌 Next: ${specials.first.title}';
      } else if (openRoutines.isNotEmpty) {
        final n = openRoutines.first;
        nextHero = '🌿 Next: ${n.title}${n.time != null ? ' · ${n.time}' : ''}';
      } else if (todayRoutines.isNotEmpty) {
        nextHero = '💚 Day handled — rest is allowed';
      } else {
        nextHero = '🌿 Your day is here whenever you are';
      }

      final specialLines = specials
          .map((e) =>
              '${e.disruptive ? '📌' : '✨'} ${e.title}')
          .join('\n');
      final missionLines = [
        if (specialLines.isNotEmpty) specialLines,
        ...todayRoutines.map((r) {
          final mark = handledIds.contains(r.id) ? '✓ ' : '• ';
          final time = r.time != null ? '  (${r.time})' : '';
          return '$mark${r.title}$time';
        }),
      ].join('\n');

      final handled = todayRoutines
          .where((r) => handledIds.contains(r.id))
          .length;
      final progress = todayRoutines.isEmpty && specials.isEmpty
          ? nextHero
          : todayRoutines.isEmpty
              ? nextHero
              : '$nextHero\n$handled of ${todayRoutines.length} handled';

      // Upcoming plans in the next forwardDays.
      String upcoming = '';
      if (forwardDays > 0) {
        final upcomingEvents = <String>[];
        for (int d = 1; d <= forwardDays; d++) {
          final futureDate = today.add(Duration(days: d));
          final dateStr = DateFormat('yyyy-MM-dd').format(futureDate);
          final events = await IsarService.getEventsForDate(dateStr);
          if (events.isNotEmpty) {
            final dayLabel = d == 1 ? 'Tomorrow' : DateFormat('EEEE').format(futureDate);
            upcomingEvents
                .add('$dayLabel: ${events.map((e) => e.title).join(", ")}');
          }
        }
        upcoming = upcomingEvents.join('\n');
      }

      // One recent memory — part of the story.
      final recentMemories = await IsarService.getAllCaptures();
      final lastMem = recentMemories.firstWhere(
        (c) =>
            c.memoryLevel != MemoryLevel.quick &&
            c.deletedAt == null &&
            !c.tags.contains('mad-vent'), // vents NEVER surface (sacred rule)
        orElse: () => QuickCapture(
            id: '', at: DateTime.now(), memoryLevel: MemoryLevel.quick),
      );
      final recentStory = lastMem.contextNote ?? lastMem.text ?? '';

      // Kind, user-type-aware summary.
      String summary =
          'You showed up. Small steps = big wins. You got this!';
      if (doneCount > 0) {
        summary = 'You showed up. $doneCount done today. You got this!';
      }
      if (settings.userType.contains('kid')) {
        summary = 'Awesome job! $doneCount wins today 🌟 You are amazing!';
      } else if (settings.userType == 'ADHD') {
        summary = 'You did it. $doneCount steps. Brain high-fives you.';
      }

      await HomeWidget.saveWidgetData<String>(
          'today_mission',
          missionLines.isEmpty
              ? 'Your day is here. Rest is allowed 🌿'
              : missionLines);
      await HomeWidget.saveWidgetData<String>(
          'today_progress', progress.isEmpty ? nextHero : progress);
      await HomeWidget.saveWidgetData<String>('summary', summary);
      await HomeWidget.saveWidgetData<String>('upcoming',
          upcoming.isEmpty ? 'Nothing planned ahead. That\'s allowed.' : upcoming);
      await HomeWidget.saveWidgetData<String>(
          'recent_memory',
          recentStory.isEmpty
              ? 'You\'ve done great things before.'
              : recentStory);

      for (final provider in _providers) {
        await HomeWidget.updateWidget(name: provider, androidName: provider);
      }
    } catch (_) {
      // Fail silent — widgets are a bonus, never a blocker.
    }
  }
}
