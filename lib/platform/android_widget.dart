import 'dart:io' show Platform;

import 'package:home_widget/home_widget.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
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
      // The widget can render before the app tree ever built (boot,
      // background update) — make sure its words follow the person's
      // language, not the default.
      L.lang = settings.appLanguage;
      final allRoutines = await IsarService.getAllRoutines();
      final forwardDays =
          settings.widgetForwardDays.clamp(0, 14); // cap to avoid stress

      // OWL TIME: the widget's "today" follows the person's day border —
      // at 01:30 it still shows tonight's list, not a fresh tomorrow.
      final today = logicalDateOf(DateTime.now(), settings.dayRolloverHour);
      final todayStr = dayKeyOf(today);

      // Today's mission: routines that apply today, as a friendly list.
      final todayRoutines =
          allRoutines.where((r) => r.isActive && r.appliesOn(today)).toList();
      final logsToday = await IsarService.getLogsForDate(todayStr);
      final handledIds = logsToday.map((l) => l.routineId).toSet();
      final doneCount =
          logsToday.where((l) => l.status == CompletionStatus.done).length;

      final missionLines = todayRoutines.map((r) {
        final mark = handledIds.contains(r.id) ? '✓ ' : '• ';
        final time = r.time != null ? '  (${r.time})' : '';
        return '$mark${r.title}$time';
      }).join('\n');

      final handled = todayRoutines
          .where((r) => handledIds.contains(r.id))
          .length;
      final progress = todayRoutines.isEmpty
          ? ''
          : L.t('$handled of ${todayRoutines.length} handled',
              '$handled מתוך ${todayRoutines.length} טופלו');

      // Upcoming plans in the next forwardDays.
      String upcoming = '';
      if (forwardDays > 0) {
        final upcomingEvents = <String>[];
        for (int d = 1; d <= forwardDays; d++) {
          final futureDate = today.add(Duration(days: d));
          final dateStr = dayKeyOf(futureDate);
          final events = await IsarService.getEventsForDate(dateStr);
          if (events.isNotEmpty) {
            final dayLabel = d == 1
                ? L.t('Tomorrow', 'מחר')
                : DateFormat('EEEE', L.isHebrew ? 'he' : 'en')
                    .format(futureDate);
            upcomingEvents
                .add('$dayLabel: ${events.map((e) => e.title).join(", ")}');
          }
        }
        upcoming = upcomingEvents.join('\n');
      }

      // One recent memory — part of the story.
      final recentMemories = await IsarService.getAllCaptures();
      final kept = visibleMemories(recentMemories);
      final lastMem = kept.isEmpty ? null : kept.first;
      final recentStory = lastMem == null ? '' : memoryWords(lastMem);

      // Kind, user-type-aware summary — at ADULT temperature for the
      // default voice (owner + his father, 2026-08-16: the cooing and
      // the את/ה slash-forms "pissed him off"). Kid and ADHD voices
      // keep their own chosen brightness.
      String summary = L.t('You showed up. Small steps count.',
          'הגעת. צעדים קטנים נחשבים.');
      if (doneCount > 0) {
        summary = L.t('You showed up. $doneCount done today.',
            'הגעת. $doneCount נעשו היום.');
      }
      if (settings.userType.contains('kid')) {
        summary = L.t('Awesome job! $doneCount wins today 🌟 You are amazing!',
            'עבודה מדהימה! $doneCount ניצחונות היום 🌟 את/ה מדהים/ה!');
      } else if (settings.userType == 'ADHD') {
        summary = L.t('You did it. $doneCount steps. Brain high-fives you.',
            'עשית את זה. $doneCount צעדים. המוח נותן לך כיף.');
      }

      await HomeWidget.saveWidgetData<String>(
          'today_mission',
          missionLines.isEmpty
              ? L.t('Nothing due today — rest is allowed 🌿',
                  'שום דבר לא מחכה היום — מותר לנוח 🌿')
              : missionLines);
      await HomeWidget.saveWidgetData<String>('today_progress', progress);
      await HomeWidget.saveWidgetData<String>('summary', summary);
      await HomeWidget.saveWidgetData<String>(
          'upcoming',
          upcoming.isEmpty
              ? L.t('Nothing planned ahead. That\'s allowed.',
                  'אין תוכניות קדימה. גם זה בסדר.')
              : upcoming);
      await HomeWidget.saveWidgetData<String>(
          'recent_memory',
          recentStory.isEmpty
              ? L.t('Nothing kept here yet.',
                  'עוד לא נשמר כאן זיכרון.')
              : recentStory);

      for (final provider in _providers) {
        await HomeWidget.updateWidget(name: provider, androidName: provider);
      }
    } catch (_) {
      // Fail silent — widgets are a bonus, never a blocker.
    }
  }
}
