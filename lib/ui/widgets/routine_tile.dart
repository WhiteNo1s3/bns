import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/routine.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/services/haptics.dart';
import 'package:bns/ui/widgets/later_today_door.dart';
import 'package:bns/services/tts_service.dart';

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
  // Today's "why" only — other days stay in the diary, not on this tile.
  final String? recentNote;
  final String? recentNoteWhen;

  /// When the person said "later" — the tile stays in place (the day is
  /// steady) and simply says when it knocks again.
  final DateTime? snoozedUntil;
  // How many things were told about this one TODAY.
  final int keptCount;
  final VoidCallback? onShowKept;
  /// Later today — still this day, a later clock. Null hides the door.
  final ValueChanged<String>? onLaterToday;
  final int rolloverHour;
  final int startHour;
  final String? dayKey;
  final DateTime? now;

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
    this.snoozedUntil,
    this.keptCount = 0,
    this.onShowKept,
    this.onLaterToday,
    this.rolloverHour = 0,
    this.startHour = 0,
    this.dayKey,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary; // the palette's own accent

    // Modern selected marking for PC (and keyboard nav): subtle teal background + border
    final cardColor = selected ? primary.withOpacity(0.08) : null;
    final border = selected
        ? Border.all(color: primary.withOpacity(0.5), width: 1.5)
        : null;

    final showLater = onLaterToday != null &&
        !isDone &&
        !skippedToday &&
        snoozedUntil == null &&
        routine.time != null;

    return Card(
      color: cardColor,
      shape: border != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: border.top, // reuse for all sides
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
      InkWell(
        onTap: onToggle,
        // The buzz IS the responsiveness: it lands the instant the press
        // registers, so the finger knows it was heard instead of waiting
        // on a sheet to appear (owner QA, 2026-08-15).
        onLongPress: () {
          BnsHaptics.longPress();
          onSkip();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          // Phone-first sizes (owner beta report, 2026-08-15: "all buttons
          // tiny"): taller rows, a bigger box, bigger words — the tile is
          // the thing a thumb meets a dozen times a day.
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: big ? 20 : 16),
          child: Row(
            children: [
              // A real checkbox — the most recognizable "done" object there
              // is. The whole row is the tap target (big-target law); the
              // box mirrors the row so both behave identically.
              IgnorePointer(
                child: Transform.scale(
                  scale: big ? 1.4 : 1.15,
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
                        fontSize: big ? 22 : 18.5,
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
                      RecurrenceUtils.describe(routine, dayKey: dayKey),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    // "Later, by my will" — said in place, no reshuffle:
                    // the tile keeps its spot and states when it knocks.
                    if (snoozedUntil != null &&
                        snoozedUntil!.isAfter(DateTime.now()) &&
                        !isDone &&
                        !skippedToday) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.update,
                              size: big ? 20 : 16,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            L.t(
                                'You asked for later — it knocks at ${DateFormat.Hm().format(snoozedUntil!)}',
                                'ביקשת מאוחר יותר — יחזור ב־${DateFormat.Hm().format(snoozedUntil!)}'),
                            style: TextStyle(
                              fontSize: big ? 15 : 12.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                          // Expanded so long Hebrew wraps instead of
                          // pushing past the row edge (RTL safety).
                          Expanded(
                            child: Text(
                              L.t('Didn\'t happen today — noted',
                                  'לא קרה היום — נרשם'),
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
                                  ? L.t('“$recentNote”', '״$recentNote״')
                                  : L.t('“$recentNote”  ·  $recentNoteWhen',
                                      '״$recentNote״  ·  $recentNoteWhen'),
                              style: TextStyle(
                                fontSize: big ? 15 : 12.5,
                                fontStyle: FontStyle.italic,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          // The app can read the kept words back — default
                          // manner, relaxed (owner: "always transcript...
                          // reading out loud the complaints").
                          // A 32px target is a target for a steady hand.
                          // Hands here are not always steady — 48 is the
                          // floor everywhere in this app (owner QA,
                          // 2026-08-14: the buttons could not be used).
                          IconButton(
                            tooltip: L.t('Hear it read aloud', 'להקריא בקול'),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 48, minHeight: 48),
                            iconSize: big ? 28 : 24,
                            icon: Icon(Icons.volume_up,
                                color: colorScheme.onSurfaceVariant),
                            onPressed: () => TtsService.speak(recentNote!),
                          ),
                        ],
                      ),
                    ],
                    // The next part of this routine, with its helping note.
                    // A skipped / missed row is answered — it must not
                    // keep a הבא badge on the remaining drink-water part.
                    if (!isDone &&
                        !skippedToday &&
                        routine.steps.isNotEmpty &&
                        stepsDone < routine.steps.length) ...[
                      const SizedBox(height: 6),
                      Text(
                        L.t(
                            'Next: ${routine.steps[stepsDone].title}'
                            '  (${stepsDone + 1} of ${routine.steps.length})',
                            'הבא: ${routine.steps[stepsDone].title}'
                            '  (${stepsDone + 1} מתוך ${routine.steps.length})'),
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
                  !skippedToday &&
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
                    child: Text(L.t('Part ✓', 'חלק ✓')),
                  ),
                ),
              // The door to everything told about this one — at the end of
              // the row, sweetly, never a scary "problems" label.
              if (keptCount > 0 && onShowKept != null)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    tooltip: L.t('What you told about this one',
                        'מה סיפרת על זה'),
                    onPressed: onShowKept,
                    iconSize: big ? 30 : 24,
                    icon: Badge(
                      label: Text('$keptCount'),
                      child: const Icon(Icons.chat_bubble_outline),
                    ),
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
        if (showLater)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: LaterTodayDoor(
              now: now ?? DateTime.now(),
              rolloverHour: rolloverHour,
              startHour: startHour,
              onPicked: onLaterToday!,
            ),
          ),
        ],
      ),
    );
  }
}
