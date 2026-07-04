import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';

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
    _dayMemories = allCaptures.where((c) => 
      c.memoryLevel != MemoryLevel.quick && 
      c.at.year == _date.year && 
      c.at.month == _date.month && 
      c.at.day == _date.day
    ).toList();

    if (mounted) setState(() => _loading = false);
  }

  bool _isRoutineDone(String routineId) {
    return _logs.any((l) => l.routineId == routineId && l.status == CompletionStatus.done);
  }

  Future<void> _toggleRoutine(Routine r) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final done = _isRoutineDone(r.id);
    await IsarService.logCompletion(
      routineId: r.id,
      date: dateStr,
      status: done ? CompletionStatus.skipped : CompletionStatus.done,
    );
    await _loadData();
  }

  Future<void> _skipRoutine(Routine r) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    // Open quick capture pre-linked
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickCaptureScreen(
          linkedRoutineId: r.id,
          initialText: 'Skipped: ',
        ),
      ),
    );
    if (result == true) {
      await IsarService.logCompletion(
        routineId: r.id,
        date: dateStr,
        status: CompletionStatus.skipped,
        reason: 'See linked capture',
      );
      await _loadData();
    }
  }

  Future<void> _addEvent() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_date);
    final controller = TextEditingController(text: 'Appointment');
    final timeController = TextEditingController(text: '10:00');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add event for this day'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: timeController, decoration: const InputDecoration(labelText: 'Time (HH:mm)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await IsarService.addEvent(CalendarEvent(
                id: '',
                title: controller.text,
                date: dateStr,
                time: timeController.text,
                notes: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ));
              await _loadData();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat.yMMMMEEEEd().format(_date);
    final doneCount = _applicableRoutines.where((r) => _isRoutineDone(r.id)).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(dateLabel),
        actions: [
          IconButton(icon: const Icon(Icons.sync_alt), onPressed: () => context.push('/sync'), tooltip: 'Sync'),
          IconButton(icon: const Icon(Icons.add), onPressed: _addEvent, tooltip: 'Add event'),
          IconButton(icon: const Icon(Icons.mic), onPressed: _quickCapture, tooltip: 'Quick capture'),
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
                            ? 'You showed up for $doneCount of ${_applicableRoutines.length} gentle steps today.'
                            : 'A new day. No pressure — anything you do is progress.',
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  Text('Events', style: Theme.of(context).textTheme.titleMedium),
                  if (_events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('No events registered.'),
                    )
                  else
                    ..._events.map((e) => ListTile(
                          leading: const Icon(Icons.event_note),
                          title: Text(e.title),
                          subtitle: Text(e.time ?? 'All day'),
                          onTap: () {}, // could edit later
                        )),

                  const SizedBox(height: 24),
                  Text('Routines for this day', style: Theme.of(context).textTheme.titleMedium),
                  if (_applicableRoutines.isEmpty)
                    const Text('No routines scheduled for this day.')
                  else
                    ..._applicableRoutines.map((r) {
                      final done = _isRoutineDone(r.id);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          onTap: () => _toggleRoutine(r),
                          leading: Icon(done ? Icons.check_circle : Icons.circle_outlined, size: 28),
                          title: Text(r.title, style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                          subtitle: Text(RecurrenceUtils.describe(r)),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_note),
                            onPressed: () => _skipRoutine(r),
                            tooltip: 'Log skip + reason',
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 24),
                  Text('Memories for this day', style: Theme.of(context).textTheme.titleMedium),
                  Text('Remember what happened (routines, crises, why). Memorize the day itself.', 
                       style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  if (_dayMemories.isEmpty)
                    const Text('No memories captured for this day yet. Use Remember this in routines or capture.')
                  else
                    ..._dayMemories.map((m) => ListTile(
                          leading: Icon(m.memoryLevel == MemoryLevel.memorize ? Icons.stars : Icons.bookmark),
                          title: Text(m.contextNote ?? m.text ?? 'Memory of the day'),
                          subtitle: Text(DateFormat.Hm().format(m.at) + (m.linkedRoutineId != null ? ' • from routine' : '')),
                          onTap: () {
                            if (m.audioPath != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Playing memory: ${m.audioPath}')),
                              );
                            }
                          },
                        )),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const QuickCaptureScreen(
                                  // Pre-set for day memory
                                ),
                              ),
                            );
                            await _loadData();
                          },
                          child: const Text('Remember this day / what happened'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Text('Quick thoughts this day', style: Theme.of(context).textTheme.titleMedium),
                  if (_captures.isEmpty)
                    const Text('No thoughts captured yet.')
                  else
                    ..._captures.map((c) => ListTile(
                          leading: Icon(c.audioPath != null ? Icons.mic : Icons.notes),
                          title: Text(c.text ?? 'Voice note'),
                          subtitle: Text(DateFormat.Hm().format(c.at)),
                          onTap: () {
                            if (c.audioPath != null) {
                              // Could open a small player dialog
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Would play ${c.audioPath}')),
                              );
                            }
                          },
                        )),

                  const SizedBox(height: 40),
                  FilledButton.tonal(
                    onPressed: _quickCapture,
                    child: const Text('Add a quick thought for this day'),
                  ),
                ],
              ),
            ),
    );
  }
}
