import 'package:flutter/material.dart';
import 'package:bns/core/care_lock.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/need_help.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// Dedicated screen for managing all routines (CRUD).
/// This is the first major feature added after core sync & retention.
/// Keeps it simple, large targets, forgiving, positive language.
/// Ties into the 2-week planning window and small data philosophy.
class RoutinesScreen extends StatefulWidget {
  /// True when arriving from the home-widget "+ Task" button: one tap on the
  /// widget should land straight in the new-routine form (dirt simple).
  final bool openNewOnStart;

  /// The caregiver's door in level 4 (owner, 2026-07-26): the day gets set
  /// up right on the person's device — no P2P, no other machine required.
  /// Reached only through a deliberate long-hold on the Today screen.
  final bool caregiverUnlock;

  const RoutinesScreen(
      {super.key, this.openNewOnStart = false, this.caregiverUnlock = false});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  List<Routine> _routines = [];
  bool _loading = true;
  // Level 4: the list belongs to the inspector — this screen shows, only.
  bool _guided = false;

  @override
  void initState() {
    super.initState();
    _loadRoutines();
    if (widget.openNewOnStart) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _addOrEditRoutine());
    }
  }

  Future<void> _loadRoutines() async {
    setState(() => _loading = true);
    final routines = await IsarService.getAllRoutines();
    final settings = await IsarService.getSettings();
    if (mounted) {
      setState(() {
        _routines = routines;
        // The caregiver's long-hold opens the same screen with hands:
        // guided view-only melts away, changes save straight to this
        // device. The flag alone is not enough — the caregiver's key must
        // have been opened this sitting (level-4 tester, 2026-08-16,
        // reached Add/Edit/Trash through a door that only checked the
        // flag). No key session → the hands stay off, whoever asks.
        _guided = settings.guidedMode &&
            !(widget.caregiverUnlock && CareState.caregiverUnlocked);
        _loading = false;
      });
    }
  }

  Future<void> _addOrEditRoutine([Routine? existing]) async {
    final result = await showDialog<Routine>(
      context: context,
      builder: (ctx) => _RoutineFormDialog(existing: existing),
    );

    if (result != null) {
      Routine saved;
      if (existing != null) {
        await IsarService.updateRoutine(result);
        saved = result;
      } else {
        saved = await IsarService.addRoutine(result);
      }
      if (saved.needsHelp && !(existing?.needsHelp ?? false)) {
        await IsarService.addCapture(buildAskedHelpCapture(
          id: '',
          at: DateTime.now(),
          aboutTitle: saved.title,
          linkedRoutineId: saved.id,
          hebrew: L.isHebrew,
        ));
      }
      await _loadRoutines();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null
                ? L.t('Routine updated. Nice work keeping things organized.',
                    'השגרה עודכנה. כל הכבוד על הסדר.')
                : L.t('New routine added. You\'ve got this.',
                    'שגרה חדשה נוספה. יש לך את זה.')),
          ),
        );
      }
    }
  }

  Future<void> _deleteRoutine(Routine routine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t('Remove this routine?', 'להסיר את השגרה הזאת?')),
        content: Text(L.t(
            'This will delete "${routine.title}". No pressure – you can always add it back.',
            'זה ימחק את "${routine.title}". בלי לחץ – תמיד אפשר להוסיף אותה בחזרה.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L.t('Cancel', 'ביטול'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            child: Text(L.t('Delete', 'מחיקה')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await IsarService.deleteRoutine(routine.id);
      await _loadRoutines();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  L.t('Routine removed. All good.', 'השגרה הוסרה. הכול בסדר.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Manage Routines', 'ניהול שגרות'),
        leading: Image.asset('assets/icon/bns_logo.png', height: 28, width: 28),
        hideOnDesktopWide: true,
        actions: [
          // Level 4: the + hides with the rest of the hands — look, don't
          // touch means the app bar too. The caregiver's hold brings it back.
          if (!_guided)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addOrEditRoutine(),
              tooltip: L.t('Add new routine', 'הוספת שגרה חדשה'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Say plainly whose hands the screen is in — and that everything
          // lands on THIS device, nothing travels anywhere.
          if (widget.caregiverUnlock)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.tertiaryContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                L.t(
                    'Caregiver setup — changes save to this device only. '
                    'What you build here is the list they will see.',
                    'הגדרת מטפל — השינויים נשמרים במכשיר הזה בלבד. '
                    'מה שבונים כאן הוא הרשימה שהם יראו.'),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onTertiaryContainer),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      // Guided mode: no adding here — the day arrives from the inspector.
      // THE RETURN DOOR, same as the day view (owner, 2026-08-18: "went
      // to routines as caregiver and couldn't get out... where is the
      // return button?"). A pushed routines room walks back out in words;
      // a routed one already has the doors/sidebar/☰ under the guarantee.
      bottomNavigationBar: Navigator.of(context).canPop()
          ? SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: Text(L.t('Back', 'חזרה'),
                    style: const TextStyle(fontSize: 17)),
              ),
            )
          : null,
      floatingActionButton: _guided
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEditRoutine(),
              icon: const Icon(Icons.add),
              label: Text(L.t('Add Routine', 'הוספת שגרה')),
            ),
    );
  }

  Widget _buildBody() {
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _routines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.list_alt, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        L.t(
                            'No routines yet.\nStart by adding one that supports you.',
                            'אין עדיין שגרות.\nאפשר להתחיל בשגרה אחת שתומכת בך.'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _addOrEditRoutine(),
                        icon: const Icon(Icons.add),
                        label: Text(L.t('Add your first routine',
                            'הוספת השגרה הראשונה שלך')),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _routines.length,
                  itemBuilder: (context, index) {
                    final r = _routines[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        // Level 4: look, don't touch — the inspector edits.
                        onTap: _guided ? null : () => _addOrEditRoutine(r),
                        leading: Icon(
                          r.isActive
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline,
                          color: r.isActive
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title:
                            Text(r.title, style: const TextStyle(fontSize: 18)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (r.description != null) Text(r.description!),
                            Text(
                              RecurrenceUtils.describe(r) +
                                  (r.time != null
                                      ? L.t(' at ${r.time}', ' בשעה ${r.time}')
                                      : ''),
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                        trailing: _guided
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent),
                                onPressed: () => _deleteRoutine(r),
                                tooltip: L.t('Delete routine', 'מחיקת שגרה'),
                              ),
                      ),
                    );
                  },
                );
  }
}

/// Simple dialog form for adding/editing a routine.
/// Large targets, clear labels, forgiving.
class _RoutineFormDialog extends StatefulWidget {
  final Routine? existing;

  const _RoutineFormDialog({this.existing});

  @override
  State<_RoutineFormDialog> createState() => _RoutineFormDialogState();
}

class _RoutineFormDialogState extends State<_RoutineFormDialog> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  RecurrenceType _recurrence = RecurrenceType.daily;
  List<int> _daysOfWeek = [];
  String? _time;
  bool _firstStepOnly = false;
  bool _isActive = true;
  bool _needHelp = false;
  // The parts of this routine — each its own entity, in order.
  final List<TextEditingController> _stepTitles = [];
  final List<TextEditingController> _stepNotes = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final r = widget.existing!;
      _titleController.text = r.title;
      _descController.text = r.description ?? '';
      _recurrence = r.recurrenceType;
      _daysOfWeek = List.from(r.daysOfWeek);
      _time = r.time;
      _firstStepOnly = r.firstStepOnlyDefault;
      _isActive = r.isActive;
      _needHelp = r.needsHelp;
      for (final s in r.steps) {
        _stepTitles.add(TextEditingController(text: s.title));
        _stepNotes.add(TextEditingController(text: s.note ?? ''));
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    for (final c in _stepTitles) {
      c.dispose();
    }
    for (final c in _stepNotes) {
      c.dispose();
    }
    super.dispose();
  }

  void _addStepRow() {
    setState(() {
      _stepTitles.add(TextEditingController());
      _stepNotes.add(TextEditingController());
    });
  }

  void _removeStepRow(int i) {
    setState(() {
      _stepTitles.removeAt(i).dispose();
      _stepNotes.removeAt(i).dispose();
    });
  }

  /// Times snap to quarter hours — 2:07 does not exist here (owner law,
  /// 2026-07-08: "I don't want ugly numbers in my application").
  static TimeOfDay _roundToQuarter(TimeOfDay t) {
    final total = ((t.hour * 60 + t.minute + 7) ~/ 15) * 15 % (24 * 60);
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  Future<void> _pickTime() async {
    final now = _roundToQuarter(TimeOfDay.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: _time != null
          ? TimeOfDay(
              hour: int.parse(_time!.split(':')[0]),
              minute: int.parse(_time!.split(':')[1]))
          : now,
    );
    if (picked != null) {
      final snapped = _roundToQuarter(picked);
      setState(() {
        _time =
            '${snapped.hour.toString().padLeft(2, '0')}:${snapped.minute.toString().padLeft(2, '0')}';
      });
      if (snapped.minute != picked.minute && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t(
                'Rounded to ${_time!} — clean quarter hours only.',
                'עוגל ל־${_time!} — רק רבעי שעה נקיים.'))));
      }
    }
  }

  /// User-facing label for a recurrence value — the enum names themselves
  /// stay untouched (they are data).
  String _recurrenceLabel(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.daily:
        return L.t('Daily', 'כל יום');
      case RecurrenceType.weekdays:
        return L.t('Weekdays', 'ימי חול');
      case RecurrenceType.weekly:
        return L.t('Weekly', 'פעם בשבוע');
      case RecurrenceType.custom:
        return L.t('Custom', 'ימים לבחירה');
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_daysOfWeek.contains(day)) {
        _daysOfWeek.remove(day);
      } else {
        _daysOfWeek.add(day);
      }
      _daysOfWeek.sort();
    });
  }

  void _save() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(L.t('Title is required – even a short one helps.',
                'צריך כותרת – גם קצרה עוזרת.'))),
      );
      return;
    }

    // FOOLPROOF (owner, 2026-07-08): a routine can never save broken.
    // Weekly/custom with no days picked would silently never appear —
    // auto-heal to daily and say so.
    var recurrence = _recurrence;
    if ((recurrence == RecurrenceType.weekly ||
            recurrence == RecurrenceType.custom) &&
        _daysOfWeek.isEmpty) {
      recurrence = RecurrenceType.daily;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'No days were picked — set to every day so it never gets lost. '
              'Edit anytime.',
              'לא נבחרו ימים — הוגדר לכל יום כדי ששום דבר לא יילך לאיבוד. '
              'אפשר לערוך בכל רגע.'))));
    }

    // Steps: empty titles are dropped; notes without titles don't count.
    final steps = <RoutineStep>[];
    for (var i = 0; i < _stepTitles.length; i++) {
      final t = _stepTitles[i].text.trim();
      if (t.isEmpty) continue;
      final n = _stepNotes[i].text.trim();
      steps.add(RoutineStep(title: t, note: n.isEmpty ? null : n));
    }

    final now = DateTime.now();
    final routine = Routine(
      id: widget.existing?.id ?? '',
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      recurrenceType: recurrence,
      daysOfWeek: _daysOfWeek,
      time: _time,
      isActive: _isActive,
      firstStepOnlyDefault: _firstStepOnly,
      steps: steps,
      tags: toggleNeedHelpTag(widget.existing?.tags ?? const [], on: _needHelp),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.pop(context, routine);
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = [
      L.t('Sun', 'א׳'),
      L.t('Mon', 'ב׳'),
      L.t('Tue', 'ג׳'),
      L.t('Wed', 'ד׳'),
      L.t('Thu', 'ה׳'),
      L.t('Fri', 'ו׳'),
      L.t('Sat', 'שבת'),
    ];

    return AlertDialog(
      title: Text(widget.existing == null
          ? L.t('Add New Routine', 'הוספת שגרה חדשה')
          : L.t('Edit Routine', 'עריכת שגרה')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: L.t('Title (keep it short and kind)',
                    'כותרת (קצרה ונעימה)'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: L.t(
                    'Description (optional – helps when memory is fuzzy)',
                    'תיאור (לא חובה – עוזר כשהזיכרון מעורפל)'),
                border: const OutlineInputBorder(),
              ),
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(needHelpLabel(hebrew: L.isHebrew)),
              subtitle: Text(L.t(
                  'I asked for help on this. Family hears only this ask.',
                  'ביקשתי עזרה בזה. המשפחה שומעת רק את הבקשה הזאת.')),
              value: _needHelp,
              onChanged: (v) => setState(() => _needHelp = v),
            ),
            const SizedBox(height: 16),
            // The parts of this routine — each part is its own thing, with
            // its own helping note, in the order they happen.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                  L.t('Parts, in order (optional):',
                      'חלקים, לפי הסדר (לא חובה):'),
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _stepTitles.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                      radius: 12,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      children: [
                        TextField(
                          controller: _stepTitles[i],
                          decoration: InputDecoration(
                            hintText: L.t('What happens in this part?',
                                'מה קורה בחלק הזה?'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _stepNotes[i],
                          decoration: InputDecoration(
                            hintText: L.t('A note that helps (optional)',
                                'פתק שעוזר (לא חובה)'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: L.t('Remove this part', 'הסרת החלק הזה'),
                    onPressed: () => _removeStepRow(i),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _addStepRow,
                icon: const Icon(Icons.add),
                label: Text(L.t('Add a part', 'הוספת חלק')),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RecurrenceType>(
              value: _recurrence,
              decoration: InputDecoration(
                  labelText: L.t('Repeats', 'תדירות'),
                  border: const OutlineInputBorder()),
              items: RecurrenceType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_recurrenceLabel(type)),
                );
              }).toList(),
              onChanged: (val) => setState(() => _recurrence = val!),
            ),
            const SizedBox(height: 12),
            if (_recurrence == RecurrenceType.weekly ||
                _recurrence == RecurrenceType.custom)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.t('On these days:', 'בימים האלה:')),
                  Wrap(
                    spacing: 4,
                    children: List.generate(7, (i) {
                      final selected = _daysOfWeek.contains(i);
                      return FilterChip(
                        label: Text(dayLabels[i]),
                        selected: selected,
                        onSelected: (_) => _toggleDay(i),
                      );
                    }),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            ListTile(
              title: Text(L.t('Preferred time (optional)',
                  'שעה מועדפת (לא חובה)')),
              subtitle: Text(_time ?? L.t('Any time', 'בכל שעה')),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade300)),
            ),
            SwitchListTile(
              title: Text(L.t('First-step-only mode', 'מצב צעד-ראשון-בלבד')),
              subtitle: Text(L.t(
                  'Helpful on overwhelming days – just do the tiniest part',
                  'עוזר בימים מציפים – עושים רק את החלק הכי קטן')),
              value: _firstStepOnly,
              onChanged: (v) => setState(() => _firstStepOnly = v),
            ),
            SwitchListTile(
              title: Text(L.t('Active', 'פעילה')),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('Cancel', 'ביטול'))),
        FilledButton(onPressed: _save, child: Text(L.t('Save', 'שמירה'))),
      ],
    );
  }
}
