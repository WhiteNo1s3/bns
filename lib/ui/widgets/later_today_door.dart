import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// Labeled door: Change the time / שינוי שעה (owner rename, 2026-08-19:
/// «עוד היום» said when, not what — the door now says what it does).
///
/// One button → the fusion sheet (owner as user, 2026-08-19: "when you
/// say עוד היום it opens the whole times in day instead of scroll box
/// elegant... I done with the long list of numbers"). The rail starts
/// at NOW — gone hours are simply not offered — and nothing ever lists
/// the whole day again. STATIC: the sheet appears, nothing glides.
///
/// [note] rides under the sheet's title. Routine mounts pass the
/// today-only truth («רק להיום — השגרה הקבועה לא משתנה»); a plan is
/// one-time by nature, so plan mounts pass nothing.
class LaterTodayDoor extends StatelessWidget {
  final DateTime now;
  final int rolloverHour;
  final int startHour;
  final ValueChanged<String> onPicked;
  final String? note;
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
    this.note,
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
          title: L.t('Change the time — when today?',
              'שינוי שעה — למתי היום?'),
          note: note,
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
        L.t('Change the time', 'שינוי שעה'),
        style: TextStyle(fontSize: 15 * textScale),
      ),
    );
  }
}
