import 'package:flutter/material.dart';
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

  const RoutinesScreen({super.key, this.openNewOnStart = false});

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
        _guided = settings.guidedMode;
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
      if (existing != null) {
        await IsarService.updateRoutine(result);
      } else {
        await IsarService.addRoutine(result);
      }
      await _loadRoutines();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null
                ? 'Routine updated. Nice work keeping things organized.'
                : 'New routine added. You\'ve got this.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteRoutine(Routine routine) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this routine?'),
        content: Text(
            'This will delete "${routine.title}". No pressure – you can always add it back.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade400),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await IsarService.deleteRoutine(routine.id);
      await _loadRoutines();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Routine removed. All good.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BnsAppBar(
        title: 'Manage Routines',
        leading: Image.asset('assets/icon/bns_logo.png', height: 28, width: 28),
        hideOnDesktopWide: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditRoutine(),
            tooltip: 'Add new routine',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routines.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.list_alt, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'No routines yet.\nStart by adding one that supports you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => _addOrEditRoutine(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add your first routine'),
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
                                  (r.time != null ? ' at ${r.time}' : ''),
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
                                tooltip: 'Delete routine',
                              ),
                      ),
                    );
                  },
                ),
      // Guided mode: no adding here — the day arrives from the inspector.
      floatingActionButton: _guided
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addOrEditRoutine(),
              icon: const Icon(Icons.add),
              label: const Text('Add Routine'),
            ),
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
            content: Text(
                'Rounded to ${_time!} — clean quarter hours only.')));
      }
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
        const SnackBar(
            content: Text('Title is required – even a short one helps.')),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No days were picked — set to every day so it never gets lost. '
              'Edit anytime.')));
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
      tags: widget.existing?.tags ?? [],
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.pop(context, routine);
  }

  @override
  Widget build(BuildContext context) {
    final dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add New Routine' : 'Edit Routine'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title (keep it short and kind)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText:
                    'Description (optional – helps when memory is fuzzy)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // The parts of this routine — each part is its own thing, with
            // its own helping note, in the order they happen.
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Parts, in order (optional):',
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
                          decoration: const InputDecoration(
                            hintText: 'What happens in this part?',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _stepNotes[i],
                          decoration: const InputDecoration(
                            hintText: 'A note that helps (optional)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Remove this part',
                    onPressed: () => _removeStepRow(i),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addStepRow,
                icon: const Icon(Icons.add),
                label: const Text('Add a part'),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<RecurrenceType>(
              value: _recurrence,
              decoration: const InputDecoration(
                  labelText: 'Repeats', border: OutlineInputBorder()),
              items: RecurrenceType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child:
                      Text(type.name[0].toUpperCase() + type.name.substring(1)),
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
                  const Text('On these days:'),
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
              title: const Text('Preferred time (optional)'),
              subtitle: Text(_time ?? 'Any time'),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade300)),
            ),
            SwitchListTile(
              title: const Text('First-step-only mode'),
              subtitle: const Text(
                  'Helpful on overwhelming days – just do the tiniest part'),
              value: _firstStepOnly,
              onChanged: (v) => setState(() => _firstStepOnly = v),
            ),
            SwitchListTile(
              title: const Text('Active'),
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
