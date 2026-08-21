import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/wake_words.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/services/wake_anchor_service.dart';

/// THE RING POPUP (owner, 2026-08-19: "there is no way to shut down the
/// alarm now its gonna drive me crazy... it suppose to be an alarm that
/// you set off, a pop up screen, no other screen than accept or snooze,
/// thats it").
///
/// Opening this screen SILENCES the ring (the insistent loop dies the
/// moment it is answered by a face) and re-arms tomorrow. Then exactly
/// two doors, huge, worded: קמתי — the day opens; עוד 10 דקות — the
/// ring returns once. No bar, no menu, no list. Nothing else.
class WakeRingScreen extends StatefulWidget {
  const WakeRingScreen({super.key});

  @override
  State<WakeRingScreen> createState() => _WakeRingScreenState();
}

class _WakeRingScreenState extends State<WakeRingScreen> {
  String _reason = '';

  @override
  void initState() {
    super.initState();
    // Seeing the screen IS the answer to the noise — quiet, immediately,
    // and tomorrow's wake is already standing again.
    NotificationsService.stopWakeRing();
    _load();
  }

  Future<void> _load() async {
    final s = await IsarService.getSettings();
    final note = s.wakeAlarmNote.trim();
    if (note.isNotEmpty) {
      if (mounted) setState(() => _reason = note);
      return;
    }
    final now = DateTime.now();
    final routines = await IsarService.getAllRoutines();
    final events = await IsarService.getAllEvents();
    final body = wakeBodyFor(
      routines: routines,
      events: events,
      day: logicalDateOf(now, s.dayRolloverHour),
      rolloverHour: s.dayRolloverHour,
      t: L.t,
    );
    if (mounted) setState(() => _reason = body);
  }

  /// קמתי — the day opens AT THIS HOUR: today's routines slide to now
  /// (owner, 2026-08-21), then home. A day anchors once; a second press
  /// just goes home.
  Future<void> _up() async {
    await WakeAnchorService.anchorToday();
    if (mounted) context.go('/');
  }

  Future<void> _snooze() async {
    await NotificationsService.snoozeWake();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = TimeOfDay.now();
    final hhmm = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    // Back cannot dead-end here either — it answers like קמתי.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        backgroundColor: cs.primaryContainer,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  L.t('Good morning', 'בוקר טוב'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer),
                ),
                const SizedBox(height: 6),
                Text(
                  hhmm,
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                if (_reason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _reason,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 18,
                        height: 1.4,
                        color:
                            cs.onPrimaryContainer.withValues(alpha: 0.85)),
                  ),
                ],
                const SizedBox(height: 40),
                FilledButton(
                  onPressed: _up,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(72)),
                  child: Text(L.t('I\'m up ✓', 'קמתי ✓'),
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _snooze,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60)),
                  child: Text(L.t('10 more minutes', 'עוד 10 דקות'),
                      style: const TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
