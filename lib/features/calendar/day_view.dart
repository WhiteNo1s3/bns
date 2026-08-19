import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/day_feed.dart';
import 'package:bns/core/day_ideas.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/day_look_tile.dart';
import 'package:bns/ui/widgets/didnt_happen_sheet.dart';
import 'package:bns/ui/widgets/gather_sheet.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';
import 'package:bns/ui/snack.dart';

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
  // THE PERSON ANSWERS: on a caregiver device the day is built here but the
  // ✓ is watched, never written (owner, 2026-08-16).
  bool _caregiverDevice = false;
  // The person's own clock (owl time): the future starts where THEIR day
  // ends, not at calendar midnight.
  int _rolloverHour = 0;
  int _startHour = 0;

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
    final settings = await IsarService.getSettings();
    _caregiverDevice = settings.caregiverDevice;
    _rolloverHour = settings.dayRolloverHour;
    _startHour = settings.dayStartHour;

    _events = await IsarService.getEventsForDate(dateStr);
    _logs = await IsarService.getLogsForDate(dateStr);
    _captures = await IsarService.getCapturesForDate(_date);
    _applicableRoutines = allRoutines.where((r) => r.appliesOn(_date)).toList();

    // Every kept thought from this day — quick notes included.
    // (Hiding "quick" made recorded memories vanish.)
    final allCaptures = await IsarService.getAllCaptures();
    _dayMemories = visibleMemories(allCaptures)
        .where((c) => captureBelongsToDate(c, _date))
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
      BnsSnack.show(context, SnackBar(
          content: Text(L.t(
              'The sound for this one is not on this device anymore.',
              'ההקלטה של זה כבר לא נמצאת במכשיר הזה.'))));
    }
  }

  /// You cannot do tomorrow's routine today — marking future days done was
  /// a real bug (owner, 2026-07-08: "you cannot move across time"). And
  /// "tomorrow" runs on the PERSON'S clock (level-1 note, 2026-08-17): at
  /// Saturday-night 02:00 the calendar says Sunday, but their Saturday is
  /// still going — Sunday has not come.
  bool get _isFutureDay => lookOnly(
      day: _date,
      now: DateTime.now(),
      rolloverHour: _rolloverHour,
      startHour: _startHour);

  /// A day already written is MEMORY (owner as user, 2026-08-18: "I can
  /// go to the days before and insert useless information"). Plans belong
  /// to days that are still coming; remembering stays open here forever.
  bool get _isPastDay => alreadyWritten(
      day: _date,
      now: DateTime.now(),
      rolloverHour: _rolloverHour,
      startHour: _startHour);

  Future<void> _toggleRoutine(Routine r) async {
    if (_caregiverDevice) {
      BnsSnack.show(context, SnackBar(
          content: Text(L.t(
              'The ✓ is written by the one doing it. It arrives here when the devices meet.',
              'את ה־✓ כותב מי שעושה. זה מגיע לכאן כשהמכשירים נפגשים.'))));
      return;
    }
    if (_isFutureDay) {
      BnsSnack.show(context, SnackBar(
          content: Text(L.t('That day hasn\'t come yet — it can wait for you.',
              'היום הזה עוד לא הגיע — הוא יחכה לך.'))));
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final done = _isRoutineDone(r.id);

    // Same gentle temper as Today: ask before marking, and un-checking
    // removes the mark entirely (never a silent flip to "skipped").
    // DONE IS A QUIET ✓ (owner law, 2026-07-08; re-affirmed in the
    // cross-tree pass 2026-08-17: "no second question"). Marking done just
    // marks it — the tile flipping IS the answer. Only taking a kept
    // answer BACK still asks, because an answer is worth one guard.
    if (done) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(r.title),
          content: Text(L.t('Take the ✓ back? That happens — no harm.',
              'להחזיר את ה־✓? זה קורה — שום נזק.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Keep it done', 'להשאיר בוצע'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Take it back', 'להחזיר'))),
          ],
        ),
      );
      if (confirmed != true) return;
    }

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
    if (_caregiverDevice) return; // the why is the person's to tell
    if (_isFutureDay) return; // future days are not ours to touch yet
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    // ONE miss door, no detour (level-1 note, 2026-08-17: the capture
    // screen "threw me to an empty save screen — the reason was gone").
    // Type or speak the why HERE; closing with words still keeps them.
    final result = await showDidntHappenSheet(
      context: context,
      title: r.title,
      confirmLabel: L.t('It didn\'t happen today', 'זה לא קרה היום'),
    );
    if (!result.skipped) return;
    // The why lives in the skip record itself — the container, not a
    // pointer. And words the person said stay theirs to see (silk):
    // they land as a need-help note too.
    await IsarService.logCompletion(
      routineId: r.id,
      date: dateStr,
      status: CompletionStatus.skipped,
      reason: result.reason,
    );
    if (result.reason != null) {
      await IsarService.addCapture(QuickCapture(
        id: '',
        at: DateTime.now(),
        text: result.reason,
        linkedRoutineId: r.id,
        tags: const ['routine', 'need-help'],
        memoryLevel: MemoryLevel.remember,
        contextNote: L.t('What got in the way of: ${r.title}',
            'מה הפריע ל: ${r.title}'),
      ));
    }
    await _loadData();
  }

  Future<void> _addEvent() async {
    // The past holds no new plans — for anyone, any hat.
    if (_isPastDay) {
      BnsSnack.show(context, SnackBar(
          content: Text(L.t(
              'A day that passed stays as it was. Plans belong to days still coming.',
              'יום שעבר נשאר כמו שהיה. תוכניות שייכות לימים שעוד באים.'))));
      return;
    }
    // Level 4: the day is built by the inspector, not here.
    final settings = await IsarService.getSettings();
    if (settings.guidedMode) {
      if (mounted) {
        BnsSnack.show(context, SnackBar(
            content: Text(L.t(
                'The plan is taken care of for you. All is well. 💚',
                'התוכנית מסודרת בשבילך. הכול בסדר. 💚'))));
      }
      return;
    }
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final controller =
        TextEditingController(text: L.t('Appointment', 'פגישה'));
    // THE FUSION SHEET, NOT A WALL OF HOURS (owner as user, 2026-08-18:
    // "a proper dropdown... instead of to show all hours the day have
    // including the past"). Planning TODAY starts at the next quarter
    // from now — gone hours are not offered at all.
    final nowMoment = DateTime.now();
    final planningToday = dateStr == logicalDayKey(nowMoment, _rolloverHour);
    final minHour = planningToday ? nowMoment.hour : 0;
    TimeOfDay picked = planningToday
        ? nextQuarterFrom(nowMoment)
        : const TimeOfDay(hour: 10, minute: 0);
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
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule, size: 20),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                label: Text(picked.format(ctx)),
                onPressed: () async {
                  final t = await showTimeFusionSheet(
                      context: ctx,
                      title: L.t('What time?', 'באיזו שעה?'),
                      initial: picked,
                      minHour: minHour);
                  if (t != null) setDialogState(() => picked = t);
                },
              ),
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
                  time: _snapToQuarter(
                      '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'),
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

  /// "What do we take?" — the list is BUILT here (tonight, calmly) and
  /// answered on the day. In guided mode the helper builds it; answering
  /// stays open to the person at every level, always.
  Future<void> _openGather(CalendarEvent plan) async {
    final settings = await IsarService.getSettings();
    if (!mounted) return;
    await showGatherSheet(
      context: context,
      plan: plan,
      canEdit: !settings.guidedMode,
      onChanged: (items) async {
        await IsarService.saveGather(plan.id, items);
        await _loadData();
      },
    );
  }

  /// Flip "family can know" on an existing event (upsert keeps the id).
  Future<void> _toggleFamilyShare(CalendarEvent e) async {
    final updated = e.copyWith(
        shareWithFamily: !e.shareWithFamily, updatedAt: DateTime.now());
    await IsarService.addEvent(updated);
    await _loadData();
    if (!mounted) return;
    BnsSnack.show(context, SnackBar(
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
      BnsSnack.show(context, 
        SnackBar(
            content: Text(L.t(
                'Day kept. You showed up.',
                'היום נשמר. היית כאן.'))),
      );
      context.push('/memories');
    }
  }

  /// One worded step OUT — back to the room this day was opened from
  /// (calendar or Today: the map with all the doors). A day reached with
  /// nothing underneath it goes home instead of nowhere.
  void _returnToMap() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    // The full ceremonial date clipped on phones (triage, 2026-08-16) —
    // the shorter form still names the day and survives a narrow bar.
    final dateLabel = DateFormat.MMMEd().format(_date);
    final doneCount =
        _applicableRoutines.where((r) => _isRoutineDone(r.id)).length;

    final viewingToday =
        DateFormat('yyyy-MM-dd').format(_date) ==
            DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      // NEVER hide this bar (owner, 2026-08-16 night: "entering a calendar
      // date in the future I cannot go back no matter what — any
      // platform"). This screen is PUSHED over the shell, so on a wide
      // desktop window the hidden bar left a room with no door at all:
      // no back arrow, and the sidebar buried underneath. A pushed screen
      // always keeps its bar — the bar IS the way back.
      //
      // AND EVERY DOOR IN IT WEARS ITS NAME (owner QA: "all buttons are
      // useless"; cross-tree pass 2026-08-17: "no unlabeled day-view
      // row"). The icon row — sync, +, book, mic — is gone: Sync was a
      // wrong-room dump, the mic duplicated the worded capture button in
      // the body, and what remains is worded. One room, few doors, names.
      appBar: BnsAppBar(
        title: dateLabel,
        actions: [
          // Walked into another day? One worded step back to now.
          if (!viewingToday)
            TextButton(
              onPressed: () {
                setState(() {
                  _date = DateTime.now();
                  _loading = true;
                });
                _loadData();
              },
              child: Text(L.t('Today', 'להיום'),
                  style: const TextStyle(fontSize: 16)),
            ),
          TextButton(
              onPressed: () => context.push(
                  '/day?date=${DateFormat('yyyy-MM-dd').format(_date)}'),
              child: Text(L.t('Diary', 'יומן'),
                  style: const TextStyle(fontSize: 16))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // No pep talk above the work (owner + his father,
                  // 2026-08-16; cross-tree pass 2026-08-17). The day opens
                  // on the day; the done-count sits with the routines it
                  // counts, as a fact.
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
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time, and whatever was written about it.
                              Text([
                                e.time ?? L.t('All day', 'כל היום'),
                                if ((e.notes ?? '').trim().isNotEmpty)
                                  e.notes!.trim(),
                              ].join(' · ')),
                              const SizedBox(height: 6),
                              // WHAT DO WE TAKE — built here, the night
                              // before, so the day itself only has to be
                              // answered (owner, 2026-08-15).
                              OutlinedButton.icon(
                                onPressed: () => _openGather(e),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48)),
                                icon: Icon(
                                    e.gatherReady
                                        ? Icons.check_circle_outline
                                        : Icons.backpack_outlined,
                                    size: 20),
                                label: Text(
                                  !e.hasGather
                                      ? L.t('What do we take?',
                                          'מה לוקחים?')
                                      : e.gatherReady
                                          ? L.t('Everything is with us 🌿',
                                              'הכול איתנו 🌿')
                                          : L.t(
                                              'What do we take? ${e.gatherTaken} of ${e.gather.length}',
                                              'מה לוקחים? ${e.gatherTaken} מתוך ${e.gather.length}'),
                                  style: const TextStyle(fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
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
                          // A PLAIN TAP NEVER SHARES (caregiver report,
                          // 2026-08-16: tapping the doctor row silently
                          // marked it family-shared — "the person thinks
                          // they broke it"). The row opens what the person
                          // actually came for — the bag. Sharing lives on
                          // its own icon, deliberately, and nowhere else.
                          onTap: () => _openGather(e),
                        )),
                  // The add-door lives WITH the list it adds to — worded,
                  // full-width, in the body (a third word in the bar
                  // overflowed phone width; the bar keeps two doors max).
                  // On a day already WRITTEN there is no door at all —
                  // the past takes no plans (owner as user, 2026-08-18);
                  // a quiet line says why, so nothing feels broken.
                  if (!_isPastDay)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton(
                        onPressed: _addEvent,
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        child: Text(L.t('Add a plan for this day',
                            'להוסיף אירוע ליום הזה')),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        L.t('A day that passed stays as it was.',
                            'יום שעבר נשאר כמו שהיה.'),
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant),
                      ),
                    ),

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            L.t('Routines for this day', 'שגרות ליום הזה'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      // Readiness as a fact: "2 of 4", never what's missing.
                      if (_applicableRoutines.isNotEmpty && !_isFutureDay)
                        Text(
                          L.t('$doneCount of ${_applicableRoutines.length}',
                              '$doneCount מתוך ${_applicableRoutines.length}'),
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                    ],
                  ),
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
                      // A day that has not come is LOOKED at (level-1 note,
                      // 2026-08-17: "מחר בלי וי ובלי עיפרון. רק להסתכל").
                      // Name + time. No box, no pencil, nothing that begs
                      // a tap — a tap only says the day can wait.
                      if (_isFutureDay) {
                        return DayLookTile(
                          title: r.title,
                          time: RecurrenceUtils.describe(r,
                              dayKey:
                                  DateFormat('yyyy-MM-dd').format(_date)),
                          onTap: () => BnsSnack.show(context, SnackBar(
                                  content: Text(dayHasNotComeLabel()))),
                        );
                      }
                      final done = _isRoutineDone(r.id);
                      final skipped = !done && _isRoutineSkipped(r.id);
                      final why = _whyForRoutine(r.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _toggleRoutine(r),
                          // On a caregiver device the state is a fact, not a
                          // control — a plain ✓ or an open dot, no box that
                          // begs to be tapped.
                          leading: Icon(
                              _caregiverDevice
                                  ? (done
                                      ? Icons.check
                                      : Icons.circle_outlined)
                                  : (done
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank),
                              color: _caregiverDevice && done
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                              size: 28),
                          title: Text(r.title,
                              style: done
                                  ? const TextStyle(
                                      decoration: TextDecoration.lineThrough)
                                  : null),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The viewed day's own clock — a later-today
                              // move shows its moved hour on that day.
                              Text(RecurrenceUtils.describe(r,
                                  dayKey:
                                      DateFormat('yyyy-MM-dd').format(_date))),
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
                          trailing: _caregiverDevice
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.edit_note),
                                  onPressed: () => _skipRoutine(r),
                                  tooltip: L.t('Log skip + reason',
                                      'לרשום שלא קרה — ולמה'),
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
                          ? L.t('Ideas for this day', 'רעיונות ליום הזה')
                          : L.t('Memories for this day', 'זיכרונות מהיום הזה'),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(
                      _isFutureDay
                          ? L.t(
                              'Write what to take, what to remember. If tomorrow '
                              'is a blackout, this list is still here.',
                              'לכתוב מה לקחת, מה לזכור. אם מחר יש בלאקאאוט — '
                              'הרשימה עדיין כאן.')
                          : L.t(
                              'Everything you kept this day lives here.',
                              'כל מה ששמרת ביום הזה חי כאן.'),
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (_dayMemories.isEmpty)
                    Text(_isFutureDay
                        ? L.t('No ideas for this day yet.',
                            'עוד אין רעיונות ליום הזה.')
                        : L.t(
                            'Nothing kept for this day yet.',
                            'עוד לא נשמר כלום ליום הזה.'))
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
                                builder: (_) => QuickCaptureScreen(
                                  forDate: DateFormat('yyyy-MM-dd').format(_date),
                                ),
                              ),
                            );
                            await _loadData();
                          },
                          child: Text(_isFutureDay
                              ? L.t('Add an idea for this day',
                                  'להוסיף רעיון ליום הזה')
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
      // THE RETURN DOOR (owner, 2026-08-17: "I cannot return when I am at
      // a day in the future, just one screen... I would like to correct
      // it with a return button"). The bar's arrow is a glyph among four
      // icons — a button wears its name. This door is pinned under the
      // day on every platform and width, cannot scroll away, and actually
      // LEAVES (the «להיום» action above only re-dates the same room).
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.tonal(
          onPressed: _returnToMap,
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56)),
          child: Text(L.t('Back', 'חזרה'),
              style: const TextStyle(fontSize: 17)),
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
      padding: EdgeInsets.zero,
      // 48 is the floor: a target smaller than a fingertip is not a button.
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      iconSize: 24,
      icon: Icon(Icons.volume_up,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onPressed: () => TtsService.speak(words),
    );
  }
}
