import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:bns/core/day_feed.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// THE HELPER'S HOME (owner, 2026-07-27: "we also want to have a caregiver
/// interface").
///
/// The same app, wearing the other hat. A caregiver opening BNS used to
/// land on THEIR OWN empty Today — useless, and quietly wrong: the routines
/// that arrive by sync are not theirs to tick. This screen answers the
/// three questions a helper actually has, in that order:
///
///   1. Is what I'm looking at current? (a stale day is a dangerous day)
///   2. How is their day going — and what didn't happen, and why?
///   3. What did they tell me, in their own words and their own voice?
///
/// It never lets the helper tick a task on the person's behalf: the record
/// of what happened belongs to the person who lived it. Building the day
/// happens in the routines editor, deliberately, one door away.
///
/// Same release as the person's app, by design — one build, one update
/// path, and a helper can always look at exactly what their person sees.
class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});

  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  bool _loading = true;
  DayFeed? _feed;
  CareGlance? _glance;
  List<Routine> _todayRoutines = const [];
  List<CompletionLog> _todayLogs = const [];
  String _personName = '';
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    final routines = await IsarService.getAllRoutines();
    final logs = await IsarService.getLogsForDate(dateStr);
    final captures = await IsarService.getAllCaptures();
    final events = await IsarService.getEventsForDate(dateStr);
    final trusted = await IsarService.getTrustedDevices();
    final allLogs = await IsarService.getAllCompletionLogs();

    if (!mounted) return;
    setState(() {
      _todayRoutines = routines.where((r) => r.appliesOn(now)).toList()
        ..sort((a, b) => (a.time ?? '99:99').compareTo(b.time ?? '99:99'));
      _todayLogs = logs;
      // A helper is trusted with the hard moments too — that is the whole
      // point of level 3 ("the frustration IS the signal").
      _feed = buildDayFeed(
        date: now,
        routines: routines,
        logs: logs,
        captures: captures,
        events: events,
        includeMadVents: true,
      );
      _glance = buildCareGlance(
        now: now,
        captures: captures,
        logs: allLogs,
        routines: routines,
        t: L.t,
      );
      _personName = trusted.isEmpty ? '' : trusted.first.name;
      _lastSync = trusted.isEmpty
          ? null
          : trusted
              .map((d) => d.lastSyncedAt)
              .reduce((a, b) => a.isAfter(b) ? a : b);
      _loading = false;
    });
  }

  /// How fresh is this picture? A helper acting on yesterday's data is the
  /// one real danger this screen can create, so it says so plainly.
  Widget _freshness(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_lastSync == null) {
      return _banner(
        cs.errorContainer,
        cs.onErrorContainer,
        Icons.link_off,
        L.t('No device is paired yet — nothing here comes from them.',
            'עדיין לא מחובר אף מכשיר — שום דבר כאן לא מגיע מהם.'),
        action: TextButton(
          onPressed: () => context.push('/sync'),
          child: Text(L.t('Connect', 'לחבר')),
        ),
      );
    }
    final age = DateTime.now().difference(_lastSync!);
    final stale = age > const Duration(hours: 12);
    final when = age.inMinutes < 60
        ? L.t('${age.inMinutes} minutes ago', 'לפני ${age.inMinutes} דקות')
        : age.inHours < 24
            ? L.t('${age.inHours} hours ago', 'לפני ${age.inHours} שעות')
            : L.t('${age.inDays} days ago', 'לפני ${age.inDays} ימים');
    return _banner(
      stale ? cs.errorContainer : cs.secondaryContainer,
      stale ? cs.onErrorContainer : cs.onSecondaryContainer,
      stale ? Icons.sync_problem : Icons.sync,
      stale
          ? L.t('This picture is from $when — their device has not reached '
              'this one since.',
              'התמונה הזאת מ$when — המכשיר שלהם לא הגיע לכאן מאז.')
          : L.t('Up to date — last heard from them $when.',
              'מעודכן — נשמע מהם לאחרונה $when.'),
    );
  }

  Widget _banner(Color bg, Color fg, IconData icon, String text,
      {Widget? action}) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
          if (action != null) action,
        ],
      ),
    );
  }

  CompletionLog? _logFor(String routineId) {
    for (final l in _todayLogs) {
      if (l.routineId == routineId) return l;
    }
    return null;
  }

  Widget _speak(String words) => IconButton(
        icon: const Icon(Icons.volume_up, size: 20),
        tooltip: L.t('Hear it read aloud', 'להקריא בקול'),
        onPressed: () => TtsService.speak(words),
      );

  Future<void> _play(String path) async {
    try {
      await AudioPlaybackService.toggle(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'That recording is not on this device.',
              'ההקלטה הזאת לא נמצאת במכשיר הזה.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = _personName.isEmpty
        ? L.t('the person you help', 'מי שאתה מלווה')
        : _personName;

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Their day', 'היום שלהם'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: L.t('Look again', 'לרענן'),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  _freshness(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      L.t('$who — ${DateFormat.MMMMEEEEd().format(DateTime.now())}',
                          '$who — ${DateFormat.MMMMEEEEd().format(DateTime.now())}'),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ),

                  // How the day is going — counted, never scored.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      L.t(
                          '${_feed?.doneCount ?? 0} done · '
                              '${_todayRoutines.length} on the list today',
                          '${_feed?.doneCount ?? 0} נעשו · '
                              '${_todayRoutines.length} ברשימה היום'),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),

                  // The gentle pattern glance — what to help with, never blame.
                  if (_glance != null && !_glance!.isEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: cs.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(L.t('Worth knowing', 'כדאי לדעת'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            for (final line in _glance!.lines)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• $line'),
                              ),
                            if (_glance!.aboutTitles.isNotEmpty)
                              Text(
                                L.t(
                                    'Mostly around: ${_glance!.aboutTitles.join(', ')}',
                                    'בעיקר סביב: ${_glance!.aboutTitles.join(', ')}'),
                                style: TextStyle(
                                    fontSize: 13, color: cs.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Today's list, as it stands for them. Read-only on purpose:
                  // what happened is theirs to say, never the helper's to fill in.
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(L.t('Their list today', 'הרשימה שלהם היום'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (_todayRoutines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(L.t(
                          'Nothing on their list today. You can build it below.',
                          'אין כלום ברשימה שלהם היום. אפשר לבנות אותה למטה.')),
                    )
                  else
                    ..._todayRoutines.map((r) {
                      final log = _logFor(r.id);
                      final done = log?.status == CompletionStatus.done;
                      final skipped = log?.status == CompletionStatus.skipped;
                      final why = (log?.reason ?? '').trim();
                      return Card(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: ListTile(
                          leading: Icon(
                            done
                                ? Icons.check_circle
                                : skipped
                                    ? Icons.wb_twilight
                                    : Icons.schedule,
                            color: done
                                ? cs.primary
                                : skipped
                                    ? cs.tertiary
                                    : cs.outline,
                          ),
                          title: Text(r.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text((r.time == null
                                      ? ''
                                      : '${r.time}  ·  ') +
                                  RecurrenceUtils.describe(r)),
                              if (skipped)
                                Text(
                                  why.isEmpty
                                      ? L.t('Didn\'t happen — no reason kept',
                                          'לא קרה — לא נשמרה סיבה')
                                      : L.t('Didn\'t happen — “$why”',
                                          'לא קרה — ״$why״'),
                                  style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: cs.tertiary),
                                ),
                            ],
                          ),
                          trailing: (skipped && why.isNotEmpty)
                              ? _speak(why)
                              : null,
                        ),
                      );
                    }),

                  // Their own words today — the reason this app exists.
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(L.t('What they told today', 'מה הם סיפרו היום'),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Builder(builder: (_) {
                    final said = (_feed?.items ?? [])
                        .where((i) =>
                            i.kind == DayFeedKind.needHelp ||
                            i.kind == DayFeedKind.diary ||
                            i.kind == DayFeedKind.thought ||
                            i.kind == DayFeedKind.madVent)
                        .toList();
                    if (said.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(L.t('Nothing said yet today.',
                            'עדיין לא נאמר כלום היום.')),
                      );
                    }
                    return Column(
                      children: [
                        for (final i in said)
                          ListTile(
                            leading: Icon(
                              i.kind == DayFeedKind.madVent
                                  ? Icons.air
                                  : i.hasAudio
                                      ? Icons.mic
                                      : Icons.notes,
                              color: i.kind == DayFeedKind.needHelp ||
                                      i.kind == DayFeedKind.madVent
                                  ? cs.tertiary
                                  : null,
                            ),
                            title: Text(i.hasWords
                                ? i.words!
                                : L.t('A voice-only moment (no words yet)',
                                    'רגע קולי בלבד (עדיין בלי מילים)')),
                            subtitle: Text(
                                '${DateFormat.Hm().format(i.at)}  ·  ${i.headline}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (i.hasWords) _speak(i.words!),
                                if (i.hasAudio)
                                  IconButton(
                                    icon: const Icon(Icons.play_circle_filled,
                                        size: 28),
                                    tooltip: L.t('Hear their voice',
                                        'לשמוע את הקול שלהם'),
                                    onPressed: () => _play(i.audioPath!),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  }),

                  // The helper's doors: build the day, read the whole thread.
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.push('/routines'),
                          icon: const Icon(Icons.list_alt),
                          label: Text(L.t('Build their day',
                              'לבנות את היום שלהם')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/day'),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(L.t('Read the whole day',
                              'לקרוא את כל היום')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/calendar'),
                          icon: const Icon(Icons.event_note),
                          label: Text(L.t('Appointments & plans',
                              'פגישות ותוכניות')),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => context.push('/sync'),
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(L.t('Connection & settings',
                              'חיבור והגדרות')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}
