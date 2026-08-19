import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => DayView(date: selected),
          ),
        )
        .then((_) => _loadEvents()); // refresh on return
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Calendar', 'לוח שנה'),
        hideOnDesktopWide: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: L.t('Sync devices', 'סנכרון מכשירים'),
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            // DON'T INVENT A PLAN (Eagered: the + auto-made a nameless
            // «פגישה חדשה / הערה» at 03:07). The + now opens the focused
            // day with the ONE add ask up — a name in front of the person,
            // the fusion time, and cancel creates nothing at all.
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        DayView(date: _focusedDay, startWithAdd: true)),
              ).then((_) => _loadEvents());
            },
            tooltip: L.t('Add an event to this day',
                'להוסיף אירוע ליום הזה'),
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar<CalendarEvent>(
            // The calendar shows the days that are actually THERE (owner
            // FINAL, 2026-07-08): 20 days of kept history, 10 days ahead.
            // No scrolling into years nobody can touch.
            firstDay: DateTime.now().subtract(const Duration(days: 20)),
            lastDay: DateTime.now().add(const Duration(days: 10)),
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
                ? Center(child: Text(L.t('Select a day', 'בחרו יום')))
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
        IsarService.getAllRoutines(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = snapshot.data![0] as List<CalendarEvent>;
        final captures = snapshot.data![1] as List<QuickCapture>;
        // THE CALENDAR MUST NOT LIE (level-1 note, 2026-08-17: Saturday
        // showed one plan while Today carried the real routines). The
        // preview tells the day whole: plans AND the routines that apply.
        final routines = (snapshot.data![2] as List<Routine>)
            .where((r) => r.appliesOn(day) && r.isActive)
            .toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(DateFormat.yMMMMEEEEd().format(day),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (events.isEmpty && captures.isEmpty && routines.isEmpty)
              Text(L.t(
                  'Nothing registered yet for this day. Tap + or go to the day view.',
                  'עוד לא נרשם כלום ליום הזה. אפשר ללחוץ על + או להיכנס לתצוגת היום.')),
            ...events.map((e) => ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(e.title),
                  subtitle: Text(e.time ?? L.t('All day', 'כל היום')),
                )),
            if (routines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(L.t('Routines', 'שגרות'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ...routines.map((r) => ListTile(
                    leading: const Icon(Icons.loop),
                    title: Text(r.title),
                    subtitle:
                        Text(RecurrenceUtils.describe(r, dayKey: dateStr)),
                  )),
            ],
            if (captures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(L.t('Quick thoughts', 'מחשבות מהירות'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ...captures.take(3).map((c) => ListTile(
                    leading:
                        Icon(c.audioPath != null ? Icons.mic : Icons.notes),
                    title: Text(c.text ?? L.t('Voice note', 'הקלטה קולית')),
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
              child: Text(L.t('Open full day view (routines + everything)',
                  'לתצוגת היום המלאה (שגרות + הכול)')),
            ),
          ],
        );
      },
    );
  }
}
