import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/features/wake/wake_controls.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/gather_sheet.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// TOMORROW — the next day's plan as ONE ENTITY, in its own room.
///
/// Owner as user, 2026-08-18: "the plans for tomorrow won't stick to
/// their entity with the steps to achieve things, the plan for tomorrow
/// should have its own screen showing the next day's plan including
/// addons... enjoyable to the user to put their non-routine things into
/// the routine in the hours they please."
///
/// So: one list, woven in the order of the PERSON'S day — routines carry
/// their steps right on them (the plan sticks to its entity), add-ons sit
/// at their chosen hour, and each plan's gather bag is built here tonight,
/// calmly. Adding never shows a wall of hours — the fusion sheet picks.
/// Nothing here can be marked done: tomorrow has not come; this room
/// BUILDS it. Built by the person, or — on a Care seat — by their helper
/// (day-building is the helper's hand; the ✓ stays the person's).
class TomorrowScreen extends StatefulWidget {
  const TomorrowScreen({super.key});

  @override
  State<TomorrowScreen> createState() => _TomorrowScreenState();
}

class _TomorrowScreenState extends State<TomorrowScreen> {
  DateTime _tomorrow = DateTime.now().add(const Duration(days: 1));
  List<Routine> _routines = [];
  List<CalendarEvent> _events = [];
  bool _loading = true;
  bool _guided = false;
  bool _caregiverDevice = false;
  int _rolloverHour = 0;

  String get _tomorrowKey => DateFormat('yyyy-MM-dd').format(_tomorrow);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await IsarService.getSettings();
    _guided = settings.guidedMode;
    _caregiverDevice = settings.caregiverDevice;
    _rolloverHour = settings.dayRolloverHour;
    // Tomorrow on the PERSON'S clock: at 01:30 with border 04:00 the
    // calendar already says a new date, but "tomorrow" is still the day
    // after this night ends.
    _tomorrow = logicalDateOf(DateTime.now(), _rolloverHour)
        .add(const Duration(days: 1));
    final all = await IsarService.getAllRoutines();
    _routines = all.where((r) => r.appliesOn(_tomorrow)).toList();
    _events = await IsarService.getEventsForDate(_tomorrowKey);
    if (mounted) setState(() => _loading = false);
  }

  /// The day woven into one order on the person's clock — a 02:00 night
  /// thing sits at the END of tomorrow, after the evening; rows with no
  /// clock close the list.
  List<Object> get _woven {
    int keyOf(String? hhmm) {
      final p = parseHhmm(hhmm);
      if (p == null) return 24 * 60;
      return owlMinutesOf(p.hour, p.minute, _rolloverHour);
    }

    final rows = <Object>[..._routines, ..._events];
    rows.sort((a, b) {
      final ta =
          a is Routine ? a.timeOn(_tomorrowKey) : (a as CalendarEvent).time;
      final tb =
          b is Routine ? b.timeOn(_tomorrowKey) : (b as CalendarEvent).time;
      return keyOf(ta).compareTo(keyOf(tb));
    });
    return rows;
  }

  /// An add-on lands in tomorrow: title (typed or spoken), an hour picked
  /// on the fusion sheet — or no hour at all — and "family can know" for
  /// the important ones. Same shape as today's plan door, one day later.
  Future<void> _addPlan() async {
    if (_guided) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'The plan is taken care of for you. All is well. 💚',
              'התוכנית מסודרת בשבילך. הכול בסדר. 💚'))));
      return;
    }
    final titleCtrl = TextEditingController();
    TimeOfDay? picked;
    var shareWithFamily = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text(L.t('A plan for tomorrow', 'תוכנית למחר')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: L.t('What\'s the plan?', 'מה התוכנית?'),
                  hintText: L.t('e.g. Blood test at the clinic',
                      'למשל: בדיקת דם במרפאה'),
                  border: const OutlineInputBorder(),
                  suffixIcon: DictationMicButton(controller: titleCtrl),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(picked == null
                        ? L.t('Pick an hour (optional)', 'לבחור שעה (רשות)')
                        : picked!.format(c)),
                    onPressed: () async {
                      final t = await showTimeFusionSheet(
                          context: c,
                          title:
                              L.t('What time tomorrow?', 'באיזו שעה מחר?'),
                          initial:
                              picked ?? const TimeOfDay(hour: 10, minute: 0));
                      if (t != null) setDlg(() => picked = t);
                    },
                  ),
                  if (picked != null)
                    TextButton(
                      onPressed: () => setDlg(() => picked = null),
                      child: Text(L.t('No hour — just tomorrow',
                          'בלי שעה — פשוט מחר')),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L.t('Family can know', 'המשפחה יכולה לדעת')),
                value: shareWithFamily,
                onChanged: (v) =>
                    setDlg(() => shareWithFamily = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Cancel', 'ביטול'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Put it in tomorrow', 'לשים במחר'))),
          ],
        ),
      ),
    );
    final title = titleCtrl.text.trim();
    if (saved != true || title.isEmpty) return;
    final now = DateTime.now();
    await IsarService.addEvent(CalendarEvent(
      id: '',
      title: title,
      date: _tomorrowKey,
      time: picked == null
          ? null
          : '${picked!.hour.toString().padLeft(2, '0')}:'
              '${picked!.minute.toString().padLeft(2, '0')}',
      shareWithFamily: shareWithFamily,
      createdAt: now,
      updatedAt: now,
    ));
    await NotificationsService.rescheduleAll();
    await _load();
  }

  /// Taking an add-on OUT is one tap with a way back — no interrogation
  /// (owner, 2026-08-18: accept-less flows, "done with thinking").
  Future<void> _removePlan(CalendarEvent e) async {
    await IsarService.deleteEvent(e.id);
    await NotificationsService.rescheduleAll();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(L.t('"${e.title}" left tomorrow.',
          '״${e.title}״ ירד ממחר.')),
      action: SnackBarAction(
        label: L.t('Put it back', 'להחזיר'),
        onPressed: () async {
          await IsarService.addEvent(e);
          await NotificationsService.rescheduleAll();
          await _load();
        },
      ),
    ));
  }

  /// "What do we take?" — the bag is BUILT here, tonight, calmly, and
  /// answered on the day (the answering is always the person's).
  Future<void> _openGather(CalendarEvent plan) async {
    await showGatherSheet(
      context: context,
      plan: plan,
      canEdit: !_guided,
      onChanged: (items) async {
        await IsarService.saveGather(plan.id, items);
        await _load();
      },
    );
  }

  void _returnToMap() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      context.go('/');
    }
  }

  Widget _clock(String? hhmm, TextTheme text, ColorScheme cs) => SizedBox(
        width: 56,
        child: Text(
          hhmm ?? L.t('—', '—'),
          textDirection: TextDirection.ltr,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: hhmm == null ? cs.onSurfaceVariant : cs.primary,
          ),
        ),
      );

  Widget _routineRow(Routine r) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clock(r.timeOn(_tomorrowKey), text, cs),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  // THE STEPS RIDE ON THE PLAN (owner: "stick to their
                  // entity with the steps to achieve things") — tomorrow
                  // is readable tonight, part by part.
                  ...r.steps.map((s) => Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          (s.note ?? '').trim().isEmpty
                              ? '· ${s.title}'
                              : '· ${s.title} — ${s.note!.trim()}',
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(L.t('routine', 'שגרה'),
                style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _planRow(CalendarEvent e) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _clock(e.time, text, cs),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if ((e.notes ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(e.notes!.trim(),
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: () => _openGather(e),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                    icon: Icon(
                        e.gatherReady
                            ? Icons.check_circle_outline
                            : Icons.backpack_outlined,
                        size: 20),
                    label: Text(
                      !e.hasGather
                          ? L.t('What do we take?', 'מה לוקחים?')
                          : L.t(
                              'What do we take? ${e.gather.length} things',
                              'מה לוקחים? ${e.gather.length} דברים'),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!_guided)
              TextButton(
                onPressed: () => _removePlan(e),
                style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44)),
                child: Text(L.t('Remove', 'להסיר'),
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final woven = _woven;
    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('The plan for tomorrow', 'התוכנית למחר'),
        hideOnDesktopWide: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // The day, named in full — tomorrow is a real day with
                  // a name, not an abstract "next".
                  Text(DateFormat.MMMMEEEEd().format(_tomorrow),
                      style: text.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      L.t(
                          'Built tonight, calmly — by morning it is already waiting.',
                          'נבנה מהערב, בנחת — בבוקר הוא כבר מחכה.'),
                      style: text.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  if (woven.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        L.t('Tomorrow is still open. You can start building it.',
                            'מחר עדיין פתוח. אפשר להתחיל לבנות אותו.'),
                        style: text.bodyMedium,
                      ),
                    )
                  else
                    ...woven.map((row) => row is Routine
                        ? _routineRow(row)
                        : _planRow(row as CalendarEvent)),
                  if (!_guided) ...[
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _addPlan,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52)),
                      child: Text(L.t('Add a plan for tomorrow',
                          'להוסיף תוכנית למחר')),
                    ),
                  ],
                  // THE WAKE keeps its seat where the day is built —
                  // tomorrow ends with choosing when it begins. Same
                  // controls as the wake room (menu door); one
                  // implementation, two doors. Not on a Care seat, not
                  // in guided mode (the host gate stands).
                  if (!_caregiverDevice && !_guided) ...[
                    const SizedBox(height: 24),
                    const WakeControls(),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
      // The room the plan was opened from is one worded step away —
      // pinned, every width, every platform (the no-dead-end guarantee).
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.tonal(
          onPressed: _returnToMap,
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child:
              Text(L.t('Back', 'חזרה'), style: const TextStyle(fontSize: 17)),
        ),
      ),
    );
  }
}
