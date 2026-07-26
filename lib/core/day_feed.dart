/// Day-as-diary spine (wave 13): one pure feed of everything said and done
/// on a day — routines handled, skip reasons, need-help notes, diary lines,
/// free captures. No Flutter, no I/O — unit-testable and reuseable by
/// Today, Day view, Explorer, and auto-summary.
///
/// Sacred: mad-vents never enter auto-summary. They only appear in a feed
/// when [includeMadVents] is true (full care / active mad mode).
library;

import 'package:bns/core/models/models.dart';

/// What kind of page this is in the day's diary.
enum DayFeedKind {
  /// Routine marked done (quiet win).
  done,

  /// Deliberate skip — a decision; reason rides along when present.
  skipped,

  /// Diary box / goal-progress line.
  diary,

  /// Long-press problem note (`need-help`).
  needHelp,

  /// Free quick thought / voice note.
  thought,

  /// Mad-mode vent — only when includeMadVents is true.
  madVent,

  /// Calendar plan for the day.
  event,
}

/// One chronological line in the day diary.
class DayFeedItem {
  final DayFeedKind kind;
  final DateTime at;
  final String headline;
  final String? words;
  final String? audioPath;
  final String? routineId;
  final String? captureId;
  final String? eventId;

  const DayFeedItem({
    required this.kind,
    required this.at,
    required this.headline,
    this.words,
    this.audioPath,
    this.routineId,
    this.captureId,
    this.eventId,
  });

  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;
  bool get hasWords => (words ?? '').trim().isNotEmpty;
}

/// A whole day, already sorted morning → night (diary order).
class DayFeed {
  final DateTime date;
  final List<DayFeedItem> items;

  const DayFeed({required this.date, required this.items});

  int get hardNoteCount =>
      items.where((i) => i.kind == DayFeedKind.needHelp || i.kind == DayFeedKind.skipped).length;

  int get doneCount => items.where((i) => i.kind == DayFeedKind.done).length;

  int get wordMomentCount => items
      .where((i) =>
          i.kind == DayFeedKind.diary ||
          i.kind == DayFeedKind.thought ||
          i.kind == DayFeedKind.needHelp ||
          i.kind == DayFeedKind.madVent)
      .length;
}

/// True when a capture is a rage vent (tag, case-insensitive).
bool isMadVent(QuickCapture c) =>
    c.tags.any((t) => t.toLowerCase() == 'mad-vent');

/// True when a capture is a diary-box line.
bool isDiaryCapture(QuickCapture c) =>
    c.tags.any((t) {
      final x = t.toLowerCase();
      return x == 'diary' || x == 'goal-progress';
    });

/// True when a capture is a problem / need-help note.
bool isNeedHelpCapture(QuickCapture c) =>
    c.tags.any((t) => t.toLowerCase() == 'need-help') && !isMadVent(c);

String _wordsOf(QuickCapture c) =>
    (c.text ?? c.transcript ?? c.contextNote ?? '').trim();

/// Build the chronological feed for one calendar day.
///
/// [includeMadVents]: person default is false. Full care and active mad mode
/// pass true so vents are available for care — never for auto-summary.
DayFeed buildDayFeed({
  required DateTime date,
  required List<Routine> routines,
  required List<CompletionLog> logs,
  required List<QuickCapture> captures,
  required List<CalendarEvent> events,
  bool includeMadVents = false,
}) {
  final dayStart = DateTime(date.year, date.month, date.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  final dateStr =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  final byId = {for (final r in routines) r.id: r};
  final items = <DayFeedItem>[];

  // Plans for the day (anchor at noon so they sit mid-day if no time).
  for (final e in events) {
    // Events may use date string or range; callers pass already day-filtered.
    DateTime at = dayStart.add(const Duration(hours: 12));
    final t = e.time;
    if (t != null && t.contains(':')) {
      final parts = t.split(':');
      final h = int.tryParse(parts[0]) ?? 12;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      at = DateTime(date.year, date.month, date.day, h, m);
    }
    items.add(DayFeedItem(
      kind: DayFeedKind.event,
      at: at,
      headline: e.title,
      words: e.notes,
      eventId: e.id,
    ));
  }

  // Completions (done / skip + reason).
  for (final l in logs) {
    if (l.date != dateStr) continue;
    final r = byId[l.routineId];
    final title = r?.title ?? '…';
    final reason = (l.reason ?? '').trim();
    final cleanReason =
        reason.isEmpty || reason == 'See linked capture' ? null : reason;
    items.add(DayFeedItem(
      kind: l.status == CompletionStatus.done
          ? DayFeedKind.done
          : DayFeedKind.skipped,
      at: l.at,
      headline: title,
      words: cleanReason,
      routineId: l.routineId,
    ));
  }

  // Captures that day.
  for (final c in captures) {
    if (c.deletedAt != null) continue;
    if (c.at.isBefore(dayStart) || !c.at.isBefore(dayEnd)) continue;
    if (isMadVent(c)) {
      if (!includeMadVents) continue;
      items.add(DayFeedItem(
        kind: DayFeedKind.madVent,
        at: c.at,
        headline: 'Vent',
        words: _wordsOf(c).isEmpty ? null : _wordsOf(c),
        audioPath: c.audioPath,
        captureId: c.id,
        routineId: c.linkedRoutineId,
      ));
      continue;
    }
    if (isDiaryCapture(c) || c.isDayMemory) {
      items.add(DayFeedItem(
        kind: DayFeedKind.diary,
        at: c.at,
        headline: c.isDayMemory ? 'Day kept' : 'Diary',
        words: _wordsOf(c).isEmpty ? null : _wordsOf(c),
        audioPath: c.audioPath,
        captureId: c.id,
        routineId: c.linkedRoutineId,
      ));
      continue;
    }
    if (isNeedHelpCapture(c)) {
      final rTitle = c.linkedRoutineId != null
          ? byId[c.linkedRoutineId!]?.title
          : null;
      items.add(DayFeedItem(
        kind: DayFeedKind.needHelp,
        at: c.at,
        headline: rTitle != null ? 'About: $rTitle' : 'What got in the way',
        words: _wordsOf(c).isEmpty ? null : _wordsOf(c),
        audioPath: c.audioPath,
        captureId: c.id,
        routineId: c.linkedRoutineId,
      ));
      continue;
    }
    // Free thought / remember / memorize not already classified.
    items.add(DayFeedItem(
      kind: DayFeedKind.thought,
      at: c.at,
      headline: c.memoryLevel == MemoryLevel.memorize
          ? 'Kept forever'
          : c.memoryLevel == MemoryLevel.remember
              ? 'Remembered'
              : 'Thought',
      words: _wordsOf(c).isEmpty ? null : _wordsOf(c),
      audioPath: c.audioPath,
      captureId: c.id,
      routineId: c.linkedRoutineId,
    ));
  }

  items.sort((a, b) => a.at.compareTo(b.at));
  return DayFeed(date: dayStart, items: items);
}

/// Auto day summary for "Memorize this day".
/// **Never** includes mad-vent text or counts vents as thoughts.
String buildDayAutoSummary({
  required DateTime date,
  required List<Routine> applicableRoutines,
  required List<CompletionLog> logs,
  required List<QuickCapture> captures,
  required List<CalendarEvent> events,
  required String Function(String en, String he) t,
  required String dayLabel,
}) {
  final dateStr =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  final doneTitles = <String>[];
  for (final r in applicableRoutines) {
    final done = logs.any(
        (l) => l.routineId == r.id && l.status == CompletionStatus.done);
    if (done) doneTitles.add(r.title);
  }
  final skipped =
      logs.where((l) => l.status == CompletionStatus.skipped).length;

  // Sacred: mad-vents never enter the summary (count or words).
  final safeCaptures = captures.where((c) => !isMadVent(c)).toList();
  final eventsSummary = events.map((e) => e.title).join(', ');

  var summary = t('Day summary for $dayLabel:\n', 'סיכום היום $dayLabel:\n');
  if (doneTitles.isNotEmpty) {
    summary += t('Completed: ${doneTitles.join(", ")}\n',
        'הושלמו: ${doneTitles.join(", ")}\n');
  }
  if (skipped > 0) {
    summary += t('Skipped $skipped on purpose (reasons kept with each one)\n',
        'דילגת על $skipped במכוון (הסיבות שמורות ליד כל אחת)\n');
  }
  if (eventsSummary.isNotEmpty) {
    summary += t('Plans: $eventsSummary\n', 'תוכניות: $eventsSummary\n');
  }
  if (safeCaptures.isNotEmpty) {
    summary += t(
        '${safeCaptures.length} thoughts kept today.\n',
        '${safeCaptures.length} מחשבות נשמרו היום.\n');
  }
  // Soft need-help signal without quoting vents or raw rage.
  final hard = safeCaptures.where(isNeedHelpCapture).length;
  if (hard > 0) {
    summary += t(
        'A few hard notes were kept so help can find them.\n',
        'כמה הערות קשות נשמרו כדי שאפשר יהיה לעזור.\n');
  }
  summary += t('You showed up. Small or big, it counts.',
      'היית כאן היום. קטן או גדול — זה נחשב.');
  // Silence unused dateStr if logs already day-filtered — keep for callers.
  assert(dateStr.isNotEmpty);
  return summary;
}

/// Gentle caregiver-only glance over recent hard notes.
/// Never a scoreboard: short soft lines, no "missed", no red failure counts
/// as guilt. Patterns only — what to help with.
class CareGlance {
  /// How many hard notes (need-help + skip reasons) in the window.
  final int hardNoteCount;

  /// Soft human lines (0–3), e.g. "Some hard notes in the morning".
  final List<String> lines;

  /// Routine titles that showed up often with problems (for care, not shame).
  final List<String> aboutTitles;

  const CareGlance({
    required this.hardNoteCount,
    required this.lines,
    required this.aboutTitles,
  });

  bool get isEmpty => hardNoteCount == 0 && lines.isEmpty;
}

/// Build a care glance from recent captures + logs (last [dayCount] days).
CareGlance buildCareGlance({
  required DateTime now,
  required List<QuickCapture> captures,
  required List<CompletionLog> logs,
  required List<Routine> routines,
  int dayCount = 7,
  required String Function(String en, String he) t,
}) {
  final start = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: dayCount - 1));
  final byId = {for (final r in routines) r.id: r};

  var hard = 0;
  var morning = 0;
  var afternoon = 0;
  var evening = 0;
  final about = <String, int>{};

  void tallyTime(DateTime at) {
    final h = at.hour;
    if (h < 12) {
      morning++;
    } else if (h < 17) {
      afternoon++;
    } else {
      evening++;
    }
  }

  void tallyRoutine(String? id) {
    if (id == null) return;
    final title = byId[id]?.title;
    if (title == null || title.isEmpty) return;
    about[title] = (about[title] ?? 0) + 1;
  }

  for (final c in captures) {
    if (c.deletedAt != null) continue;
    if (c.at.isBefore(start)) continue;
    if (isMadVent(c)) continue; // vents not in glance headlines
    // Explicit need-help tag only (not every "routine" tag).
    if (!c.tags.any((x) => x.toLowerCase() == 'need-help')) continue;
    hard++;
    tallyTime(c.at);
    tallyRoutine(c.linkedRoutineId);
  }

  for (final l in logs) {
    if (l.status != CompletionStatus.skipped) continue;
    if (l.at.isBefore(start)) continue;
    final reason = (l.reason ?? '').trim();
    if (reason.isEmpty || reason == 'See linked capture') continue;
    hard++;
    tallyTime(l.at);
    tallyRoutine(l.routineId);
  }

  final lines = <String>[];
  if (hard == 0) {
    return CareGlance(
      hardNoteCount: 0,
      lines: [
        t('No hard notes this week — quiet days are allowed too.',
            'אין הערות קשות השבוע — גם ימים שקטים מותרים.'),
      ],
      aboutTitles: const [],
    );
  }

  // Soft plural without pressure stats as a grade.
  lines.add(t(
      hard == 1
          ? 'One hard note was kept this week — that is a signal to help, not a mark.'
          : 'A few hard notes were kept this week — that is a signal to help, not a mark.',
      hard == 1
          ? 'נשמרה הערה קשה אחת השבוע — זה סימן לעזור, לא ציון.'
          : 'נשמרו כמה הערות קשות השבוע — זה סימן לעזור, לא ציון.'));

  // Time-of-day pattern (only if one bucket clearly leads).
  final buckets = {'morning': morning, 'afternoon': afternoon, 'evening': evening};
  final maxB = buckets.values.fold<int>(0, (a, b) => a > b ? a : b);
  if (maxB >= 2) {
    if (morning == maxB) {
      lines.add(t('Several of them were in the morning.',
          'כמה מהן היו בבוקר.'));
    } else if (afternoon == maxB) {
      lines.add(t('Several of them were in the afternoon.',
          'כמה מהן היו אחר הצהריים.'));
    } else if (evening == maxB) {
      lines.add(t('Several of them were in the evening.',
          'כמה מהן היו בערב.'));
    }
  }

  final ranked = about.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top = ranked.take(3).map((e) => e.key).toList();
  if (top.isNotEmpty) {
    lines.add(t('Things that came up: ${top.join(", ")}.',
        'דברים שחזרו: ${top.join(", ")}.'));
  }

  return CareGlance(
    hardNoteCount: hard,
    lines: lines.take(3).toList(),
    aboutTitles: top,
  );
}

/// Search haystack for day-thread / care search: words + reasons + transcripts.
bool dayItemMatchesQuery(DayFeedItem item, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (item.headline.toLowerCase().contains(q)) return true;
  if ((item.words ?? '').toLowerCase().contains(q)) return true;
  return false;
}
