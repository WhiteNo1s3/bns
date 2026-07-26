import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/day_feed.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// Day detail view.
/// Shows:
/// - Calendar events for the day
/// - Routines that apply on this day (with completion status)
/// - Quick captures logged this day (with audio playback)
/// Fully linked data as requested.
class DayView extends StatefulWidget {
  final DateTime date;

  const DayView({super.key, required this.date});

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  late DateTime _date;
  List<CalendarEvent> _events = [];
  List<Routine> _applicableRoutines = [];
  List<CompletionLog> _logs = [];
  List<QuickCapture> _captures = [];
  List<QuickCapture> _dayMemories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _date = widget.date;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final allRoutines = await IsarService.getAllRoutines();

    _events = await IsarService.getEventsForDate(dateStr);
    _logs = await IsarService.getLogsForDate(dateStr);
    _captures = await IsarService.getCapturesForDate(_date);
    _applicableRoutines = allRoutines.where((r) => r.appliesOn(_date)).toList();

    // Load memories for this day (remember + memorize levels)
    final allCaptures = await IsarService.getAllCaptures();
    _dayMemories = allCaptures
        .where((c) =>
            c.memoryLevel != MemoryLevel.quick &&
            c.at.year == _date.year &&
            c.at.month == _date.month &&
            c.at.day == _date.day)
        .toList();

    if (mounted) setState(() => _loading = false);
  }

  bool _isRoutineDone(String routineId) {
    return _logs.any(
        (l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  bool _isRoutineSkipped(String routineId) {
    return _logs.any((l) =>
        l.routineId == routineId && l.status == CompletionStatus.skipped);
  }

  /// The kept "why" for this routine on THIS day — so a skipped checkbox is
  /// never a blank mystery ("I just see that I didn't do it"). The skip
  /// record's own reason is the most reliable copy; linked notes back it up.
  String? _whyForRoutine(String routineId) {
    for (final l in _logs) {
      if (l.routineId != routineId) continue;
      if (l.status != CompletionStatus.skipped) continue;
      final words = (l.reason ?? '').trim();
      if (words.isNotEmpty && words != 'See linked capture') return words;
    }
    QuickCapture? best;
    for (final c in _captures) {
      if (c.linkedRoutineId != routineId) continue;
      if (!c.tags.contains('need-help')) continue;
      if (best == null || c.at.isAfter(best.at)) best = c;
    }
    if (best == null) return null;
    final words = (best.text ?? best.transcript ?? best.contextNote ?? '').trim();
    return words.isEmpty ? null : words;
  }

  /// Real playback — tap plays, tap again stops, a gone file says so.
  Future<void> _playCapture(QuickCapture c) async {
    final path = c.audioPath;
    if (path == null) return;
    try {
      await AudioPlaybackService.toggle(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'The sound for this one is not on this device anymore.',
              'ההקלטה של זה כבר לא נמצאת במכשיר הזה.'))));
    }
  }

  /// You cannot do tomorrow's routine today — marking future days done was
  /// a real bug (owner, 2026-07-08: "you cannot move across time").
  bool get _isFutureDay {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(_date.year, _date.month, _date.day).isAfter(today);
  }

  Future<void> _toggleRoutine(Routine r) async {
    if (_isFutureDay) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('That day hasn\'t come yet — it can wait for you.',
              'היום הזה עוד לא הגיע — הוא יחכה לך.'))));
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final done = _isRoutineDone(r.id);

    // Same gentle temper as Today: ask before marking, and un-checking
    // removes the mark entirely (never a silent flip to "skipped").
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(r.title),
        content: Text(done
            ? L.t('Take the ✓ back? That happens — no harm.',
                'להחזיר את ה־✓? זה קורה — שום נזק.')
            : L.t('Is it done? 🌿', 'בוצע? 🌿')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(done
                  ? L.t('Keep it done', 'להשאיר בוצע')
                  : L.t('Not yet', 'עוד לא'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(done
                  ? L.t('Take it back', 'להחזיר')
                  : L.t('Done ✓', 'בוצע ✓'))),
        ],
      ),
    );
    if (confirmed != true) return;

    if (done) {
      await IsarService.removeCompletion(routineId: r.id, date: dateStr);
    } else {
      await IsarService.logCompletion(
        routineId: r.id,
        date: dateStr,
        status: CompletionStatus.done,
      );
    }
    await _loadData();
  }

  Future<void> _skipRoutine(Routine r) async {
    if (_isFutureDay) return; // future days are not ours to touch yet
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    // Open quick capture pre-linked
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickCaptureScreen(
          linkedRoutineId: r.id,
          initialText: 'Skipped: ',
          initialTags: const ['routine', 'need-help'],
        ),
      ),
    );
    if (result == true) {
      // Put the person's own words into the skip record itself — the why
      // must live in the container, not behind a "see elsewhere" pointer.
      final captures = await IsarService.getAllCaptures();
      String? words;
      for (final c in captures) {
        if (c.linkedRoutineId == r.id) {
          words = (c.text ?? c.transcript ?? c.contextNote ?? '').trim();
          break; // captures come newest-first
        }
      }
      await IsarService.logCompletion(
        routineId: r.id,
        date: dateStr,
        status: CompletionStatus.skipped,
        reason: (words == null || words.isEmpty) ? null : words,
      );
      await _loadData();
    }
  }

  Future<void> _addEvent() async {
    // Level 4: the day is built by the inspector, not here.
    final settings = await IsarService.getSettings();
    if (settings.guidedMode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t(
                'The plan is taken care of for you. All is well. 💚',
                'התוכנית מסודרת בשבילך. הכול בסדר. 💚'))));
      }
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final controller =
        TextEditingController(text: L.t('Appointment', 'פגישה'));
    final timeController = TextEditingController(text: '10:00');
    var shareWithFamily = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(L.t('Add event for this day', 'הוספת אירוע ליום הזה')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: controller,
                  decoration:
                      InputDecoration(labelText: L.t('Title', 'כותרת'))),
              TextField(
                  controller: timeController,
                  decoration: InputDecoration(
                      labelText: L.t('Time (HH:mm)', 'שעה (HH:mm)'))),
              const SizedBox(height: 8),
              // Important things he might forget (doctor, wedding, holiday) —
              // ONLY these ever enter the family share. Rest is his business.
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L.t('Family can know', 'המשפחה יכולה לדעת')),
                subtitle: Text(
                    L.t(
                        'Goes into the family share — for important things like '
                        'doctor visits you\'d want a reminder about.',
                        'נכנס לשיתוף המשפחתי — לדברים חשובים כמו תור לרופא '
                        'שהיית רוצה תזכורת עליהם.'),
                    style: const TextStyle(fontSize: 12)),
                value: shareWithFamily,
                onChanged: (v) =>
                    setDialogState(() => shareWithFamily = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(L.t('Cancel', 'ביטול'))),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await IsarService.addEvent(CalendarEvent(
                  id: '',
                  title: controller.text,
                  date: dateStr,
                  // Quarter hours only — no ugly numbers (owner law).
                  time: _snapToQuarter(timeController.text),
                  notes: '',
                  shareWithFamily: shareWithFamily,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ));
                await _loadData();
              },
              child: Text(L.t('Add', 'הוספה')),
            ),
          ],
        ),
      ),
    );
  }

  /// 2:07 doesn't exist here — every time lands on a quarter hour.
  static String _snapToQuarter(String raw) {
    final parts = raw.trim().split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 10;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final total = ((h.clamp(0, 23) * 60 + m.clamp(0, 59) + 7) ~/ 15) * 15 %
        (24 * 60);
    return '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// Flip "family can know" on an existing event (upsert keeps the id).
  Future<void> _toggleFamilyShare(CalendarEvent e) async {
    final updated = e.copyWith(
        shareWithFamily: !e.shareWithFamily, updatedAt: DateTime.now());
    await IsarService.addEvent(updated);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(updated.shareWithFamily
            ? L.t('"${e.title}" goes into the family share.',
                '״${e.title}״ נכנס לשיתוף המשפחתי.')
            : L.t('"${e.title}" is yours only again.',
                '״${e.title}״ שוב רק שלך.'))));
  }

  Future<void> _quickCapture() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickCaptureScreen(
          linkedRoutineId: null,
          // could link to day implicitly via date
        ),
      ),
    );
    await _loadData();
  }

  Future<void> _memorizeDayWithAutoSummary() async {
    // Wave 13: one pure summary builder — mad-vents NEVER enter (sacred).
    final dayLabel = DateFormat.yMMMd().format(_date);
    final allForDay = [..._captures, ..._dayMemories];
    // Dedupe by id if a capture sits in both lists.
    final seen = <String>{};
    final unique = <QuickCapture>[];
    for (final c in allForDay) {
      if (seen.add(c.id)) unique.add(c);
    }
    final summary = buildDayAutoSummary(
      date: _date,
      applicableRoutines: _applicableRoutines,
      logs: _logs,
      captures: unique,
      events: _events,
      t: L.t,
      dayLabel: dayLabel,
    );

    final dayCapture = QuickCapture(
      id: '',
      at: DateTime.now(),
      text: summary,
      linkedEventId: null,
      linkedRoutineId: null,
      tags: ['day-memory', 'auto-summary'],
      memoryLevel: MemoryLevel.memorize,
      contextNote: L.t(
          'Auto-generated from routines, events and captures for this day.',
          'נוצר אוטומטית מהשגרות, האירועים והמחשבות של היום הזה.'),
      isDayMemory: true,
    );

    await IsarService.addCapture(dayCapture);
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L.t(
                'Day kept. You showed up.',
                'היום נשמר. היית כאן.'))),
      );
      context.push('/memories');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMMEEEEd().format(_date);
    final doneCount =
        _applicableRoutines.where((r) => _isRoutineDone(r.id)).length;

    return Scaffold(
      appBar: BnsAppBar(
        title: dateLabel,
        hideOnDesktopWide: true,
        actions: [
          IconButton(
              icon: const Icon(Icons.sync_alt),
              onPressed: () => context.push('/sync'),
              tooltip: L.t('Sync', 'סנכרון')),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: _addEvent,
              tooltip: L.t('Add event', 'הוספת אירוע')),
          IconButton(
              icon: const Icon(Icons.menu_book_outlined),
              onPressed: () => context.push(
                  '/day?date=${DateFormat('yyyy-MM-dd').format(_date)}'),
              tooltip: L.t('Day diary thread', 'שרשור יומן היום')),
          IconButton(
              icon: const Icon(Icons.mic),
              onPressed: _quickCapture,
              tooltip: L.t('Quick capture', 'מחשבה מהירה')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary header - kind and encouraging
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        doneCount > 0
                            ? L.t(
                                'You showed up for $doneCount of ${_applicableRoutines.length} gentle steps today.',
                                'עשית היום $doneCount מתוך ${_applicableRoutines.length} צעדים עדינים.')
                            : L.t(
                                'A new day. No pressure — anything you do is progress.',
                                'יום חדש. בלי לחץ — כל צעד קטן הוא התקדמות.'),
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text(L.t('Events', 'אירועים'),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_events.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(L.t('No events registered.',
                          'אין אירועים רשומים.')),
                    )
                  else
                    ..._events.map((e) => ListTile(
                          leading: const Icon(Icons.event_note),
                          title: Text(e.title),
                          subtitle: Text(e.time ?? L.t('All day', 'כל היום')),
                          trailing: IconButton(
                            icon: Icon(
                              e.shareWithFamily
                                  ? Icons.family_restroom
                                  : Icons.family_restroom_outlined,
                              color: e.shareWithFamily
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            tooltip: e.shareWithFamily
                                ? L.t('Family can know — tap to keep it yours',
                                    'המשפחה יכולה לדעת — לחיצה תחזיר את זה רק אליך')
                                : L.t('Let family know about this one',
                                    'לשתף את המשפחה בזה'),
                            onPressed: () => _toggleFamilyShare(e),
                          ),
                          onTap: () => _toggleFamilyShare(e),
                        )),

                  const SizedBox(height: 24),
                  Text(L.t('Routines for this day', 'שגרות ליום הזה'),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_isFutureDay)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        L.t('These wait for their day.',
                            'אלה מחכות ליום שלהן.'),
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  if (_applicableRoutines.isEmpty)
                    Text(L.t('No routines scheduled for this day.',
                        'אין שגרות מתוכננות ליום הזה.'))
                  else
                    ..._applicableRoutines.map((r) {
                      final done = _isRoutineDone(r.id);
                      final skipped = !done && _isRoutineSkipped(r.id);
                      final why = _whyForRoutine(r.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          enabled: !_isFutureDay,
                          onTap: () => _toggleRoutine(r),
                          leading: Icon(
                              done
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              size: 28),
                          title: Text(r.title,
                              style: done
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough)
                                  : null),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(RecurrenceUtils.describe(r)),
                              // The skip is a tag with its why right there —
                              // never just an unexplained empty box. And the
                              // why can be read aloud, relaxed.
                              if (skipped && why == null)
                                Text(
                                  L.t('Didn\'t happen — no reason was kept',
                                      'לא קרה — לא נשמרה סיבה'),
                                  style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .tertiary),
                                )
                              else if (why != null)
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        skipped
                                            ? L.t('Didn\'t happen — “$why”',
                                                'לא קרה — ״$why״')
                                            : L.t('“$why”', '״$why״'),
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: skipped
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .tertiary
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ),
                                    _SpeakButton(why),
                                  ],
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_note),
                            onPressed: () => _skipRoutine(r),
                            tooltip: L.t('Log skip + reason',
                                'לרשום שלא קרה + סיבה'),
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  // The future cannot be remembered — it hasn't happened.
                  // Ahead of time, this section holds worries and hopes,
                  // said nicely, to be met on the day itself.
                  Text(
                      _isFutureDay
                          ? L.t('Thoughts for this day ahead',
                              'מחשבות ליום שעוד יבוא')
                          : L.t('Memories for this day', 'זיכרונות מהיום הזה'),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                      _isFutureDay
                          ? L.t(
                              'No one can see the future — but a worry or a hope '
                              'can be written down now, and met gently when the day comes.',
                              'אף אחד לא רואה את העתיד — אבל דאגה או תקווה אפשר '
                              'לכתוב כבר עכשיו, ולפגוש אותן בעדינות כשהיום יגיע.')
                          : L.t(
                              'Remember what happened (routines, crises, why). Memorize the day itself.',
                              'לזכור מה קרה (שגרות, משברים, למה). לשמור את היום עצמו בזיכרון.'),
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (_dayMemories.isEmpty)
                    Text(_isFutureDay
                        ? L.t('Nothing written for this day ahead yet.',
                            'עוד לא נכתב כלום ליום הזה.')
                        : L.t(
                            'No memories captured for this day yet. Use Remember this in routines or capture.',
                            'עוד אין זיכרונות מהיום הזה. אפשר להשתמש ב"לזכור את זה" בשגרות או בלכידה.'))
                  else
                    ..._dayMemories.map((m) {
                      // Words are always there: text, or what the device
                      // engine heard, or the context — never a blank title.
                      final words =
                          (m.text ?? m.transcript ?? m.contextNote ?? '')
                              .trim();
                      return ListTile(
                        leading: Icon(m.memoryLevel == MemoryLevel.memorize
                            ? Icons.stars
                            : Icons.bookmark),
                        title: Text(words.isEmpty
                            ? L.t('A voice-only moment (no words yet)',
                                'רגע קולי בלבד (עדיין בלי מילים)')
                            : words),
                        subtitle: Text(DateFormat.Hm().format(m.at) +
                            (m.linkedRoutineId != null
                                ? L.t(' • from routine', ' • משגרה')
                                : '')),
                        trailing: words.isEmpty
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [_SpeakButton(words)],
                              ),
                        onTap: () => _playCapture(m),
                      );
                    }),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // You cannot summarize a day that hasn't happened.
                      if (!_isFutureDay) ...[
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: _memorizeDayWithAutoSummary,
                            child: Text(L.t(
                                'Memorize this day (auto summary of routines)',
                                'לשמור את היום בזיכרון (סיכום אוטומטי של השגרות)')),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QuickCaptureScreen(),
                              ),
                            );
                            await _loadData();
                          },
                          child: Text(_isFutureDay
                              ? L.t('Write a worry or a hope for this day',
                                  'לכתוב דאגה או תקווה ליום הזה')
                              : L.t('Remember this day / what happened',
                                  'לזכור את היום הזה / מה שקרה')),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text(L.t('Quick thoughts this day', 'מחשבות מהירות מהיום הזה'),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_captures.isEmpty)
                    Text(L.t('No thoughts captured yet.',
                        'עוד אין מחשבות שמורות.'))
                  else
                    ..._captures.map((c) {
                      final words =
                          (c.text ?? c.transcript ?? c.contextNote ?? '')
                              .trim();
                      return ListTile(
                        leading: Icon(
                            c.audioPath != null ? Icons.mic : Icons.notes),
                        title: Text(words.isEmpty
                            ? L.t('A voice-only moment (no words yet)',
                                'רגע קולי בלבד (עדיין בלי מילים)')
                            : words),
                        subtitle: Text(DateFormat.Hm().format(c.at)),
                        trailing: words.isEmpty
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [_SpeakButton(words)],
                              ),
                        onTap: () => _playCapture(c),
                      );
                    }),

                  const SizedBox(height: 40),
                  FilledButton.tonal(
                    onPressed: _quickCapture,
                    child: Text(L.t('Add a quick thought for this day',
                        'להוסיף מחשבה מהירה ליום הזה')),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Small unobtrusive speaker: the app reads the kept words aloud with the
/// device voice (owner: "the tts suppose to be default manner, always
/// transcript — reading out loud the complaints, relaxed"). No motion,
/// no network — just the words, spoken.
class _SpeakButton extends StatelessWidget {
  final String words;

  const _SpeakButton(this.words);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: L.t('Hear it read aloud', 'להקריא בקול'),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      iconSize: 18,
      icon: Icon(Icons.volume_up,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: () => TtsService.speak(words),
    );
  }
}
