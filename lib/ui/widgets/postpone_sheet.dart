/// The postpone sheet — a bar that FILLS, never a bar that drags.
///
/// Levels 3–4 use this most (owner, 2026-08-16), so the whole surface is
/// three ideas: a big phrase saying how long ("שעה ורבע"), a vertical bar
/// filling toward the chosen time, and two huge +/− buttons that tick it
/// by 15 minutes. Nothing here needs steady hands, nothing moves except
/// the discrete fill of the bar, and closing without choosing costs
/// nothing at all.
library;

import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/postpone.dart';
import 'package:bns/services/haptics.dart';

/// Ask "how much later?" — returns the chosen [Duration], or null when
/// the person simply closed the sheet.
Future<Duration?> showPostponeSheet({
  required BuildContext context,
  required String title,
  bool big = false,
}) {
  return showModalBottomSheet<Duration>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _PostponeSheet(title: title, big: big),
  );
}

class _PostponeSheet extends StatefulWidget {
  final String title;
  final bool big;

  const _PostponeSheet({required this.title, required this.big});

  @override
  State<_PostponeSheet> createState() => _PostponeSheetState();
}

class _PostponeSheetState extends State<_PostponeSheet> {
  /// Start at one tick — the smallest honest postpone, one tap from most
  /// real answers (30–60 minutes).
  int _ticks = 1;

  void _more() {
    if (_ticks >= kPostponeMaxTicks) return;
    BnsHaptics.tick();
    setState(() => _ticks++);
  }

  void _less() {
    if (_ticks <= 1) return;
    BnsHaptics.tick();
    setState(() => _ticks--);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = widget.big ? 1.25 : 1.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L.t('Later: ${widget.title}', 'מאוחר יותר: ${widget.title}'),
              style: TextStyle(
                  fontSize: 20 * scale, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              L.t(
                  'Nothing is marked. It simply knocks again when you said.',
                  'שום דבר לא מסומן. זה פשוט יחזור מתי שאמרת.'),
              style: TextStyle(
                  fontSize: 14 * scale,
                  height: 1.3,
                  color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 18),

            // The chosen time, said as a person says it — the one thing
            // to read on this sheet.
            Center(
              child: Text(
                L.t('In ${postponeLabel(_ticks, hebrew: false)}',
                    'בעוד ${postponeLabel(_ticks, hebrew: true)}'),
                style: TextStyle(
                    fontSize: 26 * scale, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // THE BAR — feedback only, deliberately not a touch
                // target: it fills bottom-up, one segment per tick, as a
                // discrete state change (no sliding, no animation).
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = kPostponeMaxTicks; i >= 1; i--)
                      Container(
                        width: 30 * scale,
                        height: 15 * scale,
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        decoration: BoxDecoration(
                          color: i <= _ticks
                              ? cs.primary
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 28),
                // The hands: two huge ticks. Tap, tap, tap — no aiming.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      onPressed: _ticks < kPostponeMaxTicks ? _more : null,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(96 * scale, 72 * scale),
                      ),
                      child: Text('+15',
                          style: TextStyle(
                              fontSize: 22 * scale,
                              fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 14 * scale),
                    FilledButton.tonal(
                      onPressed: _ticks > 1 ? _less : null,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(96 * scale, 72 * scale),
                      ),
                      child: Text('−15',
                          style: TextStyle(
                              fontSize: 22 * scale,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: () => Navigator.pop(
                  context,
                  Duration(minutes: _ticks * kPostponeTickMinutes)),
              icon: Icon(Icons.check, size: 26 * scale),
              style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(60 * scale)),
              label: Text(
                L.t('Remind me then', 'להזכיר לי אז'),
                style: TextStyle(fontSize: 17 * scale),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(L.t('Not now', 'לא עכשיו'),
                    style: TextStyle(fontSize: 15 * scale)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
