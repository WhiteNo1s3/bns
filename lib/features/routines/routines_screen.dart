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
    if (mounted) {
      setState(() {
        _routines = routines;
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
                        onTap: () => _addOrEditRoutine(r),
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
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => _deleteRoutine(r),
                          tooltip: 'Delete routine',
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
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
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: _time != null
          ? TimeOfDay(
              hour: int.parse(_time!.split(':')[0]),
              minute: int.parse(_time!.split(':')[1]))
          : now,
    );
    if (picked != null) {
      setState(() {
        _time =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
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

    final now = DateTime.now();
    final routine = Routine(
      id: widget.existing?.id ?? '',
      title: _titleController.text.trim(),
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      recurrenceType: _recurrence,
      daysOfWeek: _daysOfWeek,
      time: _time,
      isActive: _isActive,
      firstStepOnlyDefault: _firstStepOnly,
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
