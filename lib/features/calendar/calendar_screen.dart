import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/calendar/day_view.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// Calendar screen with month view.
/// Tapping a day opens the DayView with linked routines, events and captures.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  Map<DateTime, List<CalendarEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final all = await IsarService.getAllEvents();
    final grouped = <DateTime, List<CalendarEvent>>{};
    for (final e in all) {
      final d = DateTime.parse(e.date);
      final key = DateTime(d.year, d.month, d.day);
      grouped.putIfAbsent(key, () => []).add(e);
    }
    if (mounted) {
      setState(() => _events = grouped);
    }
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay = focused;
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayView(date: selected),
      ),
    ).then((_) => _loadEvents()); // refresh on return
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: BnsAppBar(
        title: 'Calendar',
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Sync devices',
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              // Simple add today event
              final now = DateTime.now();
              final dateStr = DateFormat('yyyy-MM-dd').format(_focusedDay);
              await IsarService.addEvent(
                CalendarEvent(
                  id: '',
                  title: 'New appointment / note',
                  date: dateStr,
                  time: '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}',
                  notes: '',
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              await _loadEvents();
              if (mounted && _selectedDay != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DayView(date: _focusedDay)),
                ).then((_) => _loadEvents());
              }
            },
            tooltip: 'Quick add event for focused day',
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar<CalendarEvent>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.monday,
            onDaySelected: _onDaySelected,
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              markerDecoration: BoxDecoration(
                color: theme.colorScheme.tertiary,
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _selectedDay == null
                ? const Center(child: Text('Select a day'))
                : _buildDayPreview(_selectedDay!),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPreview(DateTime day) {
    final dateStr = DateFormat('yyyy-MM-dd').format(day);
    return FutureBuilder(
      future: Future.wait([
        IsarService.getEventsForDate(dateStr),
        IsarService.getCapturesForDate(day),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data![0] as List<CalendarEvent>;
        final captures = snapshot.data![1] as List<QuickCapture>;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat.yMMMMEEEEd().format(day), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (events.isEmpty && captures.isEmpty)
              const Text('Nothing registered yet for this day. Tap + or go to the day view.'),
            ...events.map((e) => ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(e.title),
                  subtitle: Text(e.time ?? 'All day'),
                )),
            if (captures.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Quick thoughts', style: TextStyle(fontWeight: FontWeight.w600)),
              ...captures.take(3).map((c) => ListTile(
                    leading: Icon(c.audioPath != null ? Icons.mic : Icons.notes),
                    title: Text(c.text ?? 'Voice note'),
                    subtitle: Text(DateFormat.Hm().format(c.at)),
                  )),
            ],
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DayView(date: day)),
                ).then((_) => setState(() {}));
              },
              child: const Text('Open full day view (routines + everything)'),
            ),
          ],
        );
      },
    );
  }
}
