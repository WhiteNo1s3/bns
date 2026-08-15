import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/calendar_event.dart';
import 'package:bns/services/haptics.dart';

/// A PLAN standing in the day (owner, 2026-08-09): a doctor appointment, a
/// one-time thing — not a routine, but today it carries the same weight as
/// a gentle step. Same checkbox language as RoutineTile, same laws: tap
/// anywhere = the quiet ✓ flow; long-press = "didn't happen" with a kept
/// why; a skip is an ANSWER, shown in words, never a faked checkmark.
class PlanTile extends StatelessWidget {
  final CalendarEvent plan;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final bool big;

  const PlanTile({
    super.key,
    required this.plan,
    required this.onToggle,
    required this.onSkip,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = plan.isDone;

    return Card(
      child: InkWell(
        onTap: onToggle,
        // Same hand, same answer: a plan's long-press buzzes too.
        onLongPress: () {
          BnsHaptics.longPress();
          onSkip();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding:
              EdgeInsets.symmetric(horizontal: 16, vertical: big ? 20 : 14),
          child: Row(
            children: [
              IgnorePointer(
                child: Transform.scale(
                  scale: big ? 1.4 : 1.0,
                  child: Checkbox(value: isDone, onChanged: (_) {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: TextStyle(
                        fontSize: big ? 22 : 17,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? colorScheme.outline
                            : colorScheme.onSurface,
                        fontWeight:
                            big ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan.time == null
                          ? L.t('A plan for today', 'תוכנית להיום')
                          : L.t('A plan for today · ${plan.time}',
                              'תוכנית להיום · ${plan.time}'),
                      style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant),
                    ),
                    if (plan.isSkipped && !isDone) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.wb_twilight,
                              size: big ? 20 : 16,
                              color: colorScheme.tertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              L.t('Didn\'t happen — that\'s okay',
                                  'לא קרה — זה בסדר גמור'),
                              style: TextStyle(
                                fontSize: big ? 16 : 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (plan.answerReason != null &&
                        plan.answerReason!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        L.t('“${plan.answerReason}”', '״${plan.answerReason}״'),
                        style: TextStyle(
                          fontSize: big ? 15 : 12.5,
                          fontStyle: FontStyle.italic,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (plan.notes != null &&
                        plan.notes!.trim().isNotEmpty &&
                        !plan.isAnswered) ...[
                      const SizedBox(height: 4),
                      Text(
                        plan.notes!,
                        style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              // A little calendar mark so a plan reads as "of the day",
              // not one of the repeating steps.
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.event,
                    size: big ? 26 : 20,
                    color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
