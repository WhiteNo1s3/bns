import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/wake_anchor.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/notifications_service.dart';

/// What one קמתי did.
class WakeAnchorResult {
  final String dayKey;
  final String wokeAt;
  final String? head;
  final int moved;
  final bool alreadyAnchored;
  const WakeAnchorResult({
    required this.dayKey,
    required this.wokeAt,
    required this.head,
    required this.moved,
    required this.alreadyAnchored,
  });
}

/// ONE קמתי PER DAY (owner, 2026-08-21). Every door that means "I'm up"
/// — the ring popup, the notification's קמתי ✓, the Today door — lands
/// here: today's routines slide to the wake hour (see lib/core/
/// wake_anchor.dart), the wake is remembered for the day so a second
/// press cannot shift the day twice, and the reminders follow.
class WakeAnchorService {
  WakeAnchorService._();

  /// Days the person answered «עוד לא קמתי» this run — the door hushes
  /// until the next open. Memory only, on purpose: a new open asks again.
  static final Set<String> notYetDays = <String>{};

  static Future<bool> isAnchoredToday() async {
    final s = await IsarService.getSettings();
    final key = logicalDayKey(DateTime.now(), s.dayRolloverHour);
    return wokeAtFor(s.wokeAt, key) != null;
  }

  static Future<WakeAnchorResult> anchorToday({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final s = await IsarService.getSettings();
    final dayKey = logicalDayKey(now, s.dayRolloverHour);
    final day = logicalDateOf(now, s.dayRolloverHour);
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    final already = wokeAtFor(s.wokeAt, dayKey);
    if (already != null) {
      return WakeAnchorResult(
          dayKey: dayKey, wokeAt: already, head: null, moved: 0,
          alreadyAnchored: true);
    }

    final routines = await IsarService.getAllRoutines();
    final logs = await IsarService.getLogsForDate(dayKey);
    final answered = <String>{
      for (final l in logs)
        if (l.status == CompletionStatus.done ||
            l.status == CompletionStatus.skipped)
          l.routineId,
    };
    final head = dayHeadTime(
        routines: routines, day: day, rolloverHour: s.dayRolloverHour);
    final moves = wakeAnchoredTimes(
      routines: routines,
      day: day,
      dayKey: dayKey,
      wokeAt: hhmm,
      rolloverHour: s.dayRolloverHour,
      answeredIds: answered,
    );
    for (final r in routines) {
      final t = moves[r.id];
      if (t != null) await IsarService.addRoutine(r.postponeOn(dayKey, t));
    }
    await IsarService.updateSettings(s.copyWith(wokeAt: '$dayKey $hhmm'));
    notYetDays.remove(dayKey);
    await NotificationsService.rescheduleAll(force: true);
    AndroidBnsWidget.updateWidget();
    return WakeAnchorResult(
        dayKey: dayKey,
        wokeAt: snapToQuarterHhmm(hhmm),
        head: head,
        moved: moves.length,
        alreadyAnchored: false);
  }
}
