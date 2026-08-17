import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';

/// Hours on the person-day start door. Same set as Sync.
/// 15 is this student's day. 0 is midnight / the wiped default.
const kDayStartHourChoices = [
  0,
  6,
  8,
  10,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  20,
  21,
  22,
  23,
];

/// One kind line on Today: when does your day start?
///
/// L2 lived 2026-08-17: they stayed on Today, never opened הגדרות,
/// never reached Sync. dayStartHour stayed 0 (the wiped default, not
/// a chosen midnight). This door is that question on the day itself.
/// One tap persists the same way Sync does. After a real hour, it
/// quiets — the day is 15:00, not another maze.
class DayStartDoor extends StatelessWidget {
  final int dayStartHour;
  final ValueChanged<int> onPicked;
  final double textScale;

  const DayStartDoor({
    super.key,
    required this.dayStartHour,
    required this.onPicked,
    this.textScale = 1.0,
  });

  /// 0 is unset / the wiped default. A chosen hour quiets the door.
  bool get isUnset => dayStartHour == 0;

  @override
  Widget build(BuildContext context) {
    if (!isUnset) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          L.t('When does your day start?', 'מתי היום שלך מתחיל?'),
          style: TextStyle(
            fontSize: 16 * textScale,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in kDayStartHourChoices)
              OutlinedButton(
                onPressed: () => onPicked(h),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(72, 48),
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.outline),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  h == 0
                      ? L.t('Midnight', 'חצות')
                      : '${h.toString().padLeft(2, '0')}:00',
                  style: TextStyle(
                    fontSize: 16 * textScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
