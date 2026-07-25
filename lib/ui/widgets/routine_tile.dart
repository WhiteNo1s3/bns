import 'package:flutter/material.dart';
import 'package:bns/core/models/routine.dart';
import 'package:bns/core/utils/recurrence.dart';

/// Reusable tile for routines — a CHECKBOX row (owner, 2026-07-08: "V is
/// for checkboxes"). Tap anywhere ticks the box; long-press is only for
/// "didn't happen, and here's what got in the way".
/// Directly inspired by PillMemorizer checklist rows (stateful click, strikethrough, kind treatment).
class RoutineTile extends StatelessWidget {
  final Routine routine;
  final bool isDone;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final bool selected; // For modern PC selection marking (teal highlight)
  // The parts inside the action: how many are handled today, and the
  // button that handles the next one (null = routine has no parts).
  final int stepsDone;
  final VoidCallback? onStepDone;
  // Guided mode (level 4): the list IS the interface — bigger everything,
  // "accessible and visual" for someone for whom routines are what remains.
  final bool big;
  // "Didn't happen" is a TAG, never a checkmark (owner, 2026-07-26). The box
  // stays empty; the day is answered, gently, out loud.
  final bool skippedToday;
  // The kept "why" from the last few days — shown right on the tile so
  // seeing the task means meeting your own note again. `recentNoteWhen`
  // carries the time of day it was written ("today 14:30", "Tue 09:15").
  final String? recentNote;
  final String? recentNoteWhen;

  const RoutineTile({
    super.key,
    required this.routine,
    required this.isDone,
    required this.onToggle,
    required this.onSkip,
    this.selected = false,
    this.stepsDone = 0,
    this.onStepDone,
    this.big = false,
    this.skippedToday = false,
    this.recentNote,
    this.recentNoteWhen,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary; // consistent relaxing teal

    // Modern selected marking for PC (and keyboard nav): subtle teal background + border
    final cardColor = selected ? primary.withOpacity(0.08) : null;
    final border = selected
        ? Border.all(color: primary.withOpacity(0.5), width: 1.5)
        : null;

    return Card(
      color: cardColor,
      shape: border != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: border.top, // reuse for all sides
            )
          : null,
      child: InkWell(
        onTap: onToggle,
        onLongPress: onSkip,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: big ? 20 : 14),
          child: Row(
            children: [
              // A real checkbox — the most recognizable "done" object there
              // is. The whole row is the tap target (big-target law); the
              // box mirrors the row so both behave identically.
              IgnorePointer(
                child: Transform.scale(
                  scale: big ? 1.4 : 1.0,
                  child: Checkbox(
                    value: isDone,
                    onChanged: (_) {},
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.title,
                      style: TextStyle(
                        fontSize: big ? 22 : 17,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? colorScheme.outline
                            : colorScheme.onSurface,
                        fontWeight: big || selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      RecurrenceUtils.describe(routine),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // Today's answer when it ISN'T a ✓: a soft tag, not a
                    // checkmark. Skipped days are said, never faked.
                    if (skippedToday && !isDone) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.wb_twilight,
                              size: big ? 20 : 16,
                              color: colorScheme.tertiary),
                          const SizedBox(width: 6),
                          Text(
                            'Didn\'t happen today — that\'s okay',
                            style: TextStyle(
                              fontSize: big ? 16 : 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.tertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // The kept "why" from the last few days, with when it
                    // was written — so the person (and the caregiver) meet
                    // the note right where the task lives.
                    if (recentNote != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.sticky_note_2_outlined,
                              size: big ? 20 : 16,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              recentNoteWhen == null
                                  ? '“$recentNote”'
                                  : '“$recentNote”  ·  $recentNoteWhen',
                              style: TextStyle(
                                fontSize: big ? 15 : 12.5,
                                fontStyle: FontStyle.italic,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // The next part of this routine, with its helping note.
                    if (!isDone &&
                        routine.steps.isNotEmpty &&
                        stepsDone < routine.steps.length) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Next: ${routine.steps[stepsDone].title}'
                        '  (${stepsDone + 1} of ${routine.steps.length})',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: primary),
                      ),
                      if (routine.steps[stepsDone].note != null)
                        Text(
                          routine.steps[stepsDone].note!,
                          style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ],
                ),
              ),
              if (!isDone &&
                  routine.steps.isNotEmpty &&
                  stepsDone < routine.steps.length &&
                  onStepDone != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilledButton.tonal(
                    onPressed: onStepDone,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10)),
                    child: const Text('Part ✓'),
                  ),
                ),
              if (routine.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Chip(
                    label: Text(routine.tags.first,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
