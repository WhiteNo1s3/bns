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

  /// Opens "what do we take". Present at every care level — answering the
  /// list is the person's part even when building it is not.
  final VoidCallback? onGather;

  const PlanTile({
    super.key,
    required this.plan,
    required this.onToggle,
    required this.onSkip,
    this.big = false,
    this.onGather,
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
          // Same phone-first sizes as RoutineTile — one hand, one scale.
          padding:
              EdgeInsets.symmetric(horizontal: 16, vertical: big ? 20 : 16),
          child: Row(
            children: [
              IgnorePointer(
                child: Transform.scale(
                  scale: big ? 1.4 : 1.15,
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
                        fontSize: big ? 22 : 18.5,
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
                    // WHAT WE TAKE, right on the day. Said as readiness,
                    // never as a score of what is missing — "2 of 4 are
                    // with us" invites the next answer; "2 missing" is an
                    // accusation aimed at the person who cannot fetch them.
                    // The door shows even when the bag is still EMPTY
                    // (caregiver report, 2026-08-16: "if the bag has no
                    // door, they cannot answer") — an empty list is where
                    // the list gets built.
                    if (onGather != null && !plan.isAnswered) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: onGather,
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size.fromHeight(big ? 56 : 48),
                          foregroundColor: plan.gatherReady
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        icon: Icon(
                            plan.gatherReady
                                ? Icons.check_circle_outline
                                : Icons.backpack_outlined,
                            size: big ? 24 : 20),
                        label: Text(
                          !plan.hasGather
                              ? L.t('What do we take?', 'מה לוקחים?')
                              : plan.gatherReady
                                  ? L.t('Everything is with us 🌿',
                                      'הכול איתנו 🌿')
                                  : L.t(
                                      'What do we take? ${plan.gatherTaken} of ${plan.gather.length} are with us',
                                      'מה לוקחים? ${plan.gatherTaken} מתוך ${plan.gather.length} כבר איתנו'),
                          style: TextStyle(fontSize: big ? 16 : 13.5),
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
