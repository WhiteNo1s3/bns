import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// One kind line on Today: when does your day start?
///
/// L2 lived 2026-08-17: they stayed on Today, never opened הגדרות,
/// never reached Sync — the question must live on the day itself. The
/// wall of sixteen hour chips is gone (owner, 2026-08-18: "less
/// nightmare to look at a long list") — one worded door opens the
/// fusion picker: an hour rail to scroll, the time big in the middle,
/// one confirm wearing the hour.
///
/// Writes ONLY on the picker's explicit confirm (lived 2026-08-17
/// ~23:57: an hour landed without a tap; that is a miss — nothing here
/// fires from build, init, or a default).
///
/// Once a real hour is set the door wears the set words
/// («היום מתחיל 15:00»), so changing it later never needs הגדרות and
/// never shouts at someone whose day is already settled. A loaded 15
/// that still asks the question is a miss (lived L2 2026-08-18 ~19:16)
/// — the door is already right when it is passed hour != 0; Today
/// must hand it the store's hour, from the Person home, on this frame.
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

  Future<void> _open(BuildContext context) async {
    final picked = await showTimeFusionSheet(
      context: context,
      title: L.t('When does your day start?', 'מתי היום שלך מתחיל?'),
      initial: TimeOfDay(hour: isUnset ? 8 : dayStartHour, minute: 0),
      quarters: false,
      textScale: textScale,
    );
    if (picked != null) onPicked(picked.hour);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!isUnset) {
      // Worded, tappable — L2 lived a thin orange line they could
      // not use (2026-08-18). Same door, bigger words.
      final hh = dayStartHour.toString().padLeft(2, '0');
      return OutlinedButton.icon(
        key: const ValueKey('day-start-set'),
        onPressed: () => _open(context),
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(52 * textScale),
          alignment: AlignmentDirectional.centerStart,
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outline),
        ),
        icon: Icon(Icons.schedule, size: 20 * textScale),
        label: Text(
          L.t('The day starts at $hh:00', 'היום מתחיל $hh:00'),
          style: TextStyle(
              fontSize: 16 * textScale, fontWeight: FontWeight.w600),
        ),
      );
    }
    return OutlinedButton.icon(
      key: const ValueKey('day-start-door'),
      onPressed: () => _open(context),
      style: OutlinedButton.styleFrom(
        minimumSize: Size.fromHeight(52 * textScale),
        foregroundColor: cs.primary,
        side: BorderSide(color: cs.outline),
      ),
      icon: Icon(Icons.schedule, size: 20 * textScale),
      label: Text(
        L.t('When does your day start?', 'מתי היום שלך מתחיל?'),
        style: TextStyle(
            fontSize: 16 * textScale, fontWeight: FontWeight.w600),
      ),
    );
  }
}
