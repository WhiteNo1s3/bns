import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';

/// «היום מתחיל ב-08:00 — קמת?» (owner, 2026-08-21: "it said היום התחיל
/// בXX and a button קמתי, עוד לא קמתי").
///
/// Unanswered, it stands on top of Today like the unset day-start: a
/// question that needs answering may interrupt. קמתי slides today's
/// routines to this hour (the service does the work); עוד לא קמתי hushes
/// the door until the next open. Once answered it is a quiet worded line
/// in the footer — the truth, not a door.
class WakeAnchorDoor extends StatelessWidget {
  /// The usual clock of the day's first routine — where the shape begins.
  final String headHhmm;

  /// The wake already kept for today ('HH:mm'), or null while unanswered.
  final String? anchoredHhmm;
  final VoidCallback onUp;
  final VoidCallback onNotYet;
  final double textScale;

  const WakeAnchorDoor({
    super.key,
    required this.headHhmm,
    required this.anchoredHhmm,
    required this.onUp,
    required this.onNotYet,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final anchored = anchoredHhmm;
    if (anchored != null) {
      return Row(
        key: const ValueKey('wake-anchor-set'),
        children: [
          Icon(Icons.wb_sunny_outlined, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L.t('Up at $anchored — the list moved there. Today only.',
                  'קמת ב-$anchored — הרשימה זזה לשם. רק להיום.'),
              style: TextStyle(
                  fontSize: 14 * textScale, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return Card(
      key: const ValueKey('wake-anchor-ask'),
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              L.t('Your day starts at $headHhmm.', 'היום מתחיל ב-$headHhmm.'),
              style: TextStyle(
                  fontSize: 18 * textScale,
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: 4),
            Text(
              L.t(
                  'Up? The list moves to the hour you woke. The usual routine stays as it is.',
                  'קמת? הרשימה תזוז לשעה שקמת בה. השגרה הקבועה נשארת כמו שהיא.'),
              style: TextStyle(
                  fontSize: 14 * textScale,
                  height: 1.35,
                  color: cs.onSecondaryContainer),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onUp,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: Text(L.t('I\'m up', 'קמתי'),
                        style: TextStyle(fontSize: 17 * textScale)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: onNotYet,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: Text(L.t('Not up yet', 'עוד לא קמתי'),
                        style: TextStyle(fontSize: 16 * textScale)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
