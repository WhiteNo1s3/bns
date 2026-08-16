import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/routine.dart';

/// Big, calm "what's next" for Today.
///
/// Design choice (owner left it to us, 2026-07-27): **clean, not decorated**.
/// TBI / dementia / fog — busy heroes compete with the task. One soft
/// primaryContainer surface, large type, two clear actions (done / problem).
/// No stickers, no badges, no motion.
class NextHeroCard extends StatelessWidget {
  final Routine routine;
  final int stepsDone;
  final String? helpingNote;
  final String? recentNote;
  final VoidCallback onDone;
  final VoidCallback onProblem;
  final VoidCallback? onStepDone;
  final double textScale;

  /// This one was already STARTED and left in the middle (owner, 2026-07-29:
  /// "I did half the things to go to bed and couldn't come back — it's like
  /// a bug in my brain"). Half-finished work used to vanish the moment the
  /// screen changed; now it comes back on top and says so, so nobody has to
  /// remember where they were.
  final bool resuming;

  const NextHeroCard({
    super.key,
    required this.routine,
    required this.onDone,
    required this.onProblem,
    this.stepsDone = 0,
    this.helpingNote,
    this.recentNote,
    this.onStepDone,
    this.textScale = 1.0,
    this.resuming = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = routine.time;
    final hasParts = routine.steps.isNotEmpty &&
        stepsDone < routine.steps.length;
    final nextPart = hasParts ? routine.steps[stepsDone] : null;
    final partNote = nextPart?.note?.trim();
    final help = (helpingNote ?? partNote ?? routine.description)?.trim();

    return Card(
      elevation: 0,
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.primary.withValues(alpha: 0.18), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              resuming
                  ? L.t('You started this', 'התחלת את זה')
                  : L.t('Next', 'הבא'),
              style: TextStyle(
                fontSize: 13 * textScale,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: cs.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
            if (resuming)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  L.t('Pick up where you left off — nothing was lost.',
                      'אפשר להמשיך מאיפה שהפסקת — שום דבר לא אבד.'),
                  style: TextStyle(
                    fontSize: 13 * textScale,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            if (time != null)
              Text(
                time,
                style: TextStyle(
                  fontSize: 15 * textScale,
                  fontWeight: FontWeight.w500,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            Text(
              routine.title,
              style: TextStyle(
                fontSize: 26 * textScale,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: cs.onPrimaryContainer,
              ),
            ),
            if (nextPart != null) ...[
              const SizedBox(height: 8),
              Text(
                L.t(
                    'Part ${stepsDone + 1} of ${routine.steps.length}: ${nextPart.title}',
                    'חלק ${stepsDone + 1} מתוך ${routine.steps.length}: ${nextPart.title}'),
                style: TextStyle(
                  fontSize: 16 * textScale,
                  fontWeight: FontWeight.w600,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ],
            if (help != null && help.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                help,
                style: TextStyle(
                  fontSize: 15 * textScale,
                  height: 1.35,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.85),
                ),
              ),
            ],
            if (recentNote != null && recentNote!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                L.t('You wrote: “${recentNote!.trim()}”',
                    'כתבת: ״${recentNote!.trim()}״'),
                style: TextStyle(
                  fontSize: 14 * textScale,
                  fontStyle: FontStyle.italic,
                  color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                ),
              ),
            ],
            const SizedBox(height: 18),
            // One primary action: done. Problem is secondary but large enough.
            if (hasParts && onStepDone != null)
              FilledButton(
                onPressed: onStepDone,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: Text(
                  L.t('This part is done', 'החלק הזה בוצע'),
                  style: TextStyle(
                      fontSize: 17 * textScale, fontWeight: FontWeight.w600),
                ),
              )
            else
              FilledButton(
                onPressed: onDone,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
                child: Text(
                  L.t('It\'s done', 'בוצע'),
                  style: TextStyle(
                      fontSize: 17 * textScale, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onProblem,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: cs.onPrimaryContainer,
                side: BorderSide(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.35)),
              ),
              child: Text(
                L.t('Something got in the way', 'משהו הפריע'),
                style: TextStyle(fontSize: 15 * textScale),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet list of the next few after the hero — not competing with Next.
class ComingUpStrip extends StatelessWidget {
  final List<({Routine routine, String? timeLabel})> items;
  final double textScale;

  const ComingUpStrip({
    super.key,
    required this.items,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          L.t('Coming up', 'בהמשך'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        ...items.map((item) {
          final t = item.timeLabel;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.circle,
                    size: 8, color: cs.primary.withValues(alpha: 0.55)),
                const SizedBox(width: 10),
                if (t != null) ...[
                  Text(
                    t,
                    style: TextStyle(
                      fontSize: 14 * textScale,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    item.routine.title,
                    style: TextStyle(
                      fontSize: 16 * textScale,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

/// Pick open (not done, not skipped) routines in "what's next" clock order.
List<Routine> openRoutinesInNextOrder({
  required List<Routine> todays,
  required Set<String> doneIds,
  required Set<String> skippedIds,
  // Postponed by the person's own will (owner, 2026-08-16): while a
  // snooze runs, the hero stops offering that one — "later" that keeps
  // getting suggested anyway is not later, it is nagging.
  Set<String> snoozedIds = const {},
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final nowMin = n.hour * 60 + n.minute;

  int minutes(Routine r) {
    if (r.time == null) return 24 * 60;
    final p = r.time!.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  final open = todays
      .where((r) =>
          !doneIds.contains(r.id) &&
          !skippedIds.contains(r.id) &&
          !snoozedIds.contains(r.id))
      .toList();

  open.sort((a, b) {
    final am = minutes(a), bm = minutes(b);
    int rank(int m) => m >= 24 * 60 ? 2 : (m >= nowMin ? 0 : 1);
    final ra = rank(am), rb = rank(bm);
    if (ra != rb) return ra.compareTo(rb);
    return am.compareTo(bm);
  });
  return open;
}

/// Gentle empty hero when the open list is empty.
class DayClearCard extends StatelessWidget {
  final bool guided;
  final double textScale;

  const DayClearCard({
    super.key,
    this.guided = false,
    this.textScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          guided
              ? L.t(
                  'Nothing waiting on the list right now. All is well.',
                  'שום דבר לא מחכה ברשימה כרגע. הכול טוב.')
              : L.t(
                  'Nothing waiting right now. Rest is allowed.',
                  'שום דבר לא מחכה כרגע. מותר לנוח.'),
          style: TextStyle(
            fontSize: 18 * textScale,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: cs.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
