import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/later_today.dart';

/// Labeled door: Later today / עוד היום.
///
/// STATIC — the picker appears in place, no slide. Quarter-hour chips
/// only; 48dp floor. A button wears its name (never a lone clock glyph).
class LaterTodayDoor extends StatefulWidget {
  final DateTime now;
  final int rolloverHour;
  final int startHour;
  final ValueChanged<String> onPicked;
  final double textScale;

  /// Hero sits on primaryContainer — match that ink so the door does
  /// not shout a second color.
  final bool onHero;

  const LaterTodayDoor({
    super.key,
    required this.now,
    required this.rolloverHour,
    this.startHour = 0,
    required this.onPicked,
    this.textScale = 1.0,
    this.onHero = false,
  });

  @override
  State<LaterTodayDoor> createState() => _LaterTodayDoorState();
}

class _LaterTodayDoorState extends State<LaterTodayDoor> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slots = laterTodaySlots(
      now: widget.now,
      rolloverHour: widget.rolloverHour,
      startHour: widget.startHour,
    );
    final ink = widget.onHero ? cs.onPrimaryContainer : cs.primary;
    final border = widget.onHero
        ? cs.onPrimaryContainer.withValues(alpha: 0.35)
        : cs.outline;

    if (!_open) {
      return OutlinedButton(
        onPressed: () => setState(() => _open = true),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: ink,
          side: BorderSide(color: border),
        ),
        child: Text(
          L.t('Later today', 'עוד היום'),
          style: TextStyle(fontSize: 15 * widget.textScale),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slots.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              L.t('Nothing later left today. That\'s okay.',
                  'אין יותר שעות היום. זה בסדר.'),
              style: TextStyle(
                fontSize: 15 * widget.textScale,
                height: 1.35,
                color: widget.onHero
                    ? cs.onPrimaryContainer.withValues(alpha: 0.85)
                    : cs.onSurfaceVariant,
              ),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hhmm in slots)
                OutlinedButton(
                  onPressed: () {
                    widget.onPicked(hhmm);
                    if (mounted) setState(() => _open = false);
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(72, 48),
                    foregroundColor: ink,
                    side: BorderSide(color: border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(
                    hhmm,
                    style: TextStyle(
                      fontSize: 16 * widget.textScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => setState(() => _open = false),
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: ink,
          ),
          child: Text(
            L.t('Close', 'סגירה'),
            style: TextStyle(fontSize: 15 * widget.textScale),
          ),
        ),
      ],
    );
  }
}
