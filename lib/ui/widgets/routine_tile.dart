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

  const RoutineTile({
    super.key,
    required this.routine,
    required this.isDone,
    required this.onToggle,
    required this.onSkip,
    this.selected = false,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // A real checkbox — the most recognizable "done" object there
              // is. The whole row is the tap target (big-target law); the
              // box mirrors the row so both behave identically.
              IgnorePointer(
                child: Checkbox(
                  value: isDone,
                  onChanged: (_) {},
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
                        fontSize: 17,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone
                            ? colorScheme.outline
                            : colorScheme.onSurface,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
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
                  ],
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
