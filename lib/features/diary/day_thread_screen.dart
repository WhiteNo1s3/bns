import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/day_feed.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// The day-as-diary thread: everything said and done on one day, morning → night.
///
/// Person view: no mad-vents (unless mad mode is still on).
/// Full care: vents available in the thread, never auto-summarized.
/// Care glance (soft patterns, no scoreboard) only when full care is on.
///
/// Static: date changes in place — no slide transitions (vestibular law).
class DayThreadScreen extends StatefulWidget {
  /// YYYY-MM-DD or null = today.
  final String? initialDate;

  const DayThreadScreen({super.key, this.initialDate});

  @override
  State<DayThreadScreen> createState() => _DayThreadScreenState();
}

class _DayThreadScreenState extends State<DayThreadScreen> {
  late DateTime _date;
  DayFeed? _feed;
  CareGlance? _glance;
  bool _loading = true;
  bool _fullCare = false;
  bool _madActive = false;
  bool _guided = false;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _date = _parseDate(widget.initialDate) ?? DateTime.now();
    _date = DateTime(_date.year, _date.month, _date.day);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  bool get _isFuture {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _date.isAfter(today);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await IsarService.getSettings();
    final madUntil = settings.madModeUntil;
    final madActive =
        madUntil != null && madUntil.isAfter(DateTime.now());
    // VENTS NEVER COME BACK AT THE PERSON (caregiver report, 2026-08-16:
    // "Memories showed the rants back... feels like the app told on
    // them"). fullCareMode is true on the PERSON'S own level-3 device too
    // — the rants are the signal for the HELPER, so they show only where
    // the helper is: on the caregiver device. On the person's device a
    // vent surfaces only while their own mad mode is still burning.
    final includeMad =
        (settings.fullCareMode && settings.caregiverDevice) || madActive;

    final routines = await IsarService.getAllRoutines();
    final logs = await IsarService.getLogsForDate(_dateStr);
    final captures = await IsarService.getCapturesForDate(_date);
    final events = await IsarService.getEventsForDate(_dateStr);

    final feed = buildDayFeed(
      date: _date,
      routines: routines,
      logs: logs,
      captures: captures,
      events: events,
      includeMadVents: includeMad,
    );

    CareGlance? glance;
    if (settings.fullCareMode) {
      final allCaptures = await IsarService.getAllCaptures();
      final allLogs = await IsarService.getAllCompletionLogs();
      glance = buildCareGlance(
        now: DateTime.now(),
        captures: allCaptures,
        logs: allLogs,
        routines: routines,
        dayCount: 7,
        t: L.t,
      );
    }

    if (!mounted) return;
    setState(() {
      _feed = feed;
      _glance = glance;
      _fullCare = settings.fullCareMode;
      _madActive = madActive;
      _guided = settings.guidedMode;
      _loading = false;
    });
  }

  void _shiftDay(int delta) {
    setState(() {
      _date = _date.add(Duration(days: delta));
    });
    _load();
  }

  Future<void> _play(String? path) async {
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

  List<DayFeedItem> get _visible {
    final items = _feed?.items ?? const <DayFeedItem>[];
    if (_query.trim().isEmpty) return items;
    return items.where((i) => dayItemMatchesQuery(i, _query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final label = DateFormat.yMMMMEEEEd(L.isHebrew ? 'he' : 'en').format(_date);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Day diary', 'יומן היום'),
        hideOnDesktopWide: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: L.t('Open calendar', 'לפתוח לוח שנה'),
            onPressed: () => context.push('/calendar'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
                children: [
                  // Date strip — change in place, no slide animation.
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        tooltip: L.t('Previous day', 'היום הקודם'),
                        onPressed: () => _shiftDay(-1),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              label,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            if (_isFuture)
                              Text(
                                L.t('This day hasn\'t come yet.',
                                    'היום הזה עוד לא הגיע.'),
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        tooltip: L.t('Next day', 'היום הבא'),
                        onPressed: () => _shiftDay(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        final n = DateTime.now();
                        setState(() {
                          _date = DateTime(n.year, n.month, n.day);
                        });
                        _load();
                      },
                      child: Text(L.t('Jump to today', 'לחזור להיום')),
                    ),
                  ),

                  // Kind orientation for the person.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        _guided
                            ? L.t(
                                'Everything said and done — kept gently. The list on Today is still the main door.',
                                'כל מה שנאמר ונעשה — נשמר בעדינות. הרשימה במסך היום עדיין הדלת הראשית.')
                            : L.t(
                                'Everything you said and did this day lives here. Big or small — it belongs.',
                                'כל מה שאמרת ועשית ביום הזה חי כאן. גדול או קטן — יש לו מקום.'),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),

                  // Care glance — full care only, never a patient scoreboard.
                  if (_fullCare && _glance != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: cs.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L.t('For the people who care',
                                  'לאנשים שדואגים'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ..._glance!.lines.map((line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(line,
                                      style: TextStyle(
                                          color: cs.onSecondaryContainer)),
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (_madActive && !_fullCare) ...[
                    const SizedBox(height: 8),
                    Text(
                      L.t(
                          'Mad mode is on — today\'s vents stay in this thread until they burn out.',
                          'מצב כעס פעיל — הפריקות של היום נשארות בשרשור עד שיימחקו מעצמן.'),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],

                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: L.t(
                          'Search words, reasons, plans…',
                          'חיפוש מילים, סיבות, תוכניות…'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),

                  const SizedBox(height: 16),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _query.trim().isNotEmpty
                            ? L.t('Nothing matched. Try another word.',
                                'שום דבר לא התאים. אפשר לנסות מילה אחרת.')
                            : _isFuture
                                ? L.t(
                                    'Nothing on this day yet — that is fine.',
                                    'עדיין אין כלום ביום הזה — וזה בסדר.')
                                : L.t(
                                    'A quiet day so far. Anything you keep will show up here.',
                                    'יום שקט בינתיים. כל מה שיישמר יופיע כאן.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._visible.map((item) => _DayThreadTile(
                          item: item,
                          onPlay: () => _play(item.audioPath),
                          onSpeak: item.hasWords
                              ? () => TtsService.speak(item.words!)
                              : null,
                        )),

                  const SizedBox(height: 16),
                  if (!_guided)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/capture'),
                      icon: const Icon(Icons.mic_none),
                      label: Text(L.t('Add a thought', 'להוסיף מחשבה')),
                    ),
                ],
              ),
            ),
    );
  }
}

class _DayThreadTile extends StatelessWidget {
  final DayFeedItem item;
  final VoidCallback onPlay;
  final VoidCallback? onSpeak;

  const _DayThreadTile({
    required this.item,
    required this.onPlay,
    this.onSpeak,
  });

  IconData get _icon {
    switch (item.kind) {
      case DayFeedKind.done:
        return Icons.check_circle_outline;
      case DayFeedKind.skipped:
        return Icons.front_hand_outlined;
      case DayFeedKind.diary:
        return Icons.menu_book_outlined;
      case DayFeedKind.needHelp:
        return Icons.sticky_note_2_outlined;
      case DayFeedKind.thought:
        return item.hasAudio ? Icons.mic_none : Icons.notes;
      case DayFeedKind.madVent:
        return Icons.whatshot_outlined;
      case DayFeedKind.event:
        return Icons.event_note_outlined;
    }
  }

  String _kindLabel() {
    switch (item.kind) {
      case DayFeedKind.done:
        return L.t('Done', 'בוצע');
      case DayFeedKind.skipped:
        return L.t('Didn\'t happen', 'לא קרה');
      case DayFeedKind.diary:
        return L.t('Diary', 'יומן');
      case DayFeedKind.needHelp:
        return L.t('Hard note', 'הערה קשה');
      case DayFeedKind.thought:
        return L.t('Thought', 'מחשבה');
      case DayFeedKind.madVent:
        return L.t('Vent', 'פריקה');
      case DayFeedKind.event:
        return L.t('Plan', 'תוכנית');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = DateFormat.Hm().format(item.at);
    final isMad = item.kind == DayFeedKind.madVent;
    final isHard = item.kind == DayFeedKind.needHelp ||
        (item.kind == DayFeedKind.skipped && item.hasWords);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isMad
          ? cs.errorContainer.withValues(alpha: 0.35)
          : isHard
              ? cs.tertiaryContainer.withValues(alpha: 0.4)
              : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon,
                color: isMad
                    ? cs.onErrorContainer
                    : cs.primary,
                size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        time,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _kindLabel(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.headline,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (item.hasWords) ...[
                    const SizedBox(height: 4),
                    Text(
                      '“${item.words}”',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurface,
                      ),
                    ),
                  ] else if (item.hasAudio)
                    Text(
                      L.t('A voice-only moment (no words yet)',
                          'רגע קולי בלבד (עדיין בלי מילים)'),
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (onSpeak != null)
              IconButton(
                tooltip: L.t('Hear it read aloud', 'להקריא בקול'),
                icon: const Icon(Icons.volume_up, size: 20),
                onPressed: onSpeak,
              ),
            if (item.hasAudio)
              IconButton(
                tooltip: L.t('Play voice', 'להשמיע'),
                icon: const Icon(Icons.play_circle_outline, size: 22),
                onPressed: onPlay,
              ),
          ],
        ),
      ),
    );
  }
}
