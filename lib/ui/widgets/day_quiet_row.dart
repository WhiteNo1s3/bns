import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';

/// ONE LINE PER THING (owner, 2026-08-19: "I am seeing all the daily on
/// my phone so crumbed out with things inside it so I cannot tell what
/// is next is what isn't... all I wanted is to check what left in my
/// day"). The quiet row is the day's list at levels 1–2: the clock, the
/// name, the state — nothing else. Steps live on the Next hero (they
/// are a doing-tool, not list decoration); kept words live in the day's
/// words; reasons live one door away.
///
/// Laws held: tap is the quiet ✓ (no second question); the pencil is
/// the one miss-door; THE DAY STAYS STEADY — an answered row dims IN
/// PLACE, it never moves; 48dp floor on the touch targets.
class DayQuietRow extends StatelessWidget {
  final String? time;
  final String title;
  final bool done;
  final bool skipped;

  /// «חלק 2 מתוך 3» while a routine is mid-steps — one small fact.
  final String? stepNote;

  /// Keyboard walk highlight (desktop Ctrl+G flow).
  final bool selected;
  final double textScale;
  final VoidCallback onTap;
  final VoidCallback? onSkip;
  final VoidCallback? onGather;
  final VoidCallback? onLongPress;

  const DayQuietRow({
    super.key,
    required this.time,
    required this.title,
    required this.done,
    required this.skipped,
    this.stepNote,
    this.selected = false,
    this.textScale = 1.0,
    required this.onTap,
    this.onSkip,
    this.onGather,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final answered = done || skipped;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: selected
            ? BoxDecoration(
                border: Border.all(color: cs.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Opacity(
          opacity: answered ? 0.55 : 1,
          child: Row(
            children: [
              SizedBox(
                width: 56,
                child: Text(
                  time ?? '—',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 16 * textScale,
                    fontWeight: FontWeight.w700,
                    color: time == null ? cs.onSurfaceVariant : cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17 * textScale,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (stepNote != null)
                      Text(
                        stepNote!,
                        style: TextStyle(
                            fontSize: 12 * textScale,
                            color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (skipped)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: Text(
                    L.t('didn\'t happen', 'לא קרה'),
                    style: TextStyle(
                        fontSize: 12.5 * textScale, color: cs.tertiary),
                  ),
                )
              else if (done)
                Icon(Icons.check_rounded, size: 22, color: cs.primary)
              else ...[
                if (onGather != null)
                  IconButton(
                    onPressed: onGather,
                    tooltip: L.t('What do we take?', 'מה לוקחים?'),
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(Icons.backpack_outlined,
                        size: 22, color: cs.onSurfaceVariant),
                  ),
                if (onSkip != null)
                  IconButton(
                    onPressed: onSkip,
                    tooltip:
                        L.t('Didn\'t happen + why', 'לא קרה — ולמה'),
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: Icon(Icons.edit_note,
                        size: 24, color: cs.onSurfaceVariant),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
