import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// Labeled door: Later today / עוד היום.
///
/// One button → the fusion sheet (owner as user, 2026-08-19: "when you
/// say עוד היום it opens the whole times in day instead of scroll box
/// elegant... I done with the long list of numbers"). The rail starts
/// at NOW — gone hours are simply not offered — and nothing ever lists
/// the whole day again. STATIC: the sheet appears, nothing glides.
class LaterTodayDoor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = onHero ? cs.onPrimaryContainer : cs.primary;
    final border = onHero
        ? cs.onPrimaryContainer.withValues(alpha: 0.35)
        : cs.outline;

    return OutlinedButton(
      onPressed: () async {
        // The moment of the TAP decides which hours are still real —
        // the widget may have been built a while ago.
        final pressNow = DateTime.now();
        final t = await showTimeFusionSheet(
          context: context,
          title: L.t('Later today — when?', 'עוד היום — מתי?'),
          initial: nextQuarterFrom(pressNow),
          minHour: pressNow.hour,
        );
        if (t == null) return;
        onPicked('${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}');
      },
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: ink,
        side: BorderSide(color: border),
      ),
      child: Text(
        L.t('Later today', 'עוד היום'),
        style: TextStyle(fontSize: 15 * textScale),
      ),
    );
  }
}
