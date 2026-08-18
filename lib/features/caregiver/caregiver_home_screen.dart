import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:bns/core/day_feed.dart';
import 'package:bns/core/need_help.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/utils/recurrence.dart';
import 'package:bns/data/local/care_profiles.dart';
import 'package:bns/data/sync/lan_sync_service.dart';
import 'package:bns/features/caregiver/care_alarm_door.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/later_today_door.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';
import 'package:bns/ui/snack.dart';

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
  List<QuickCapture> _asks = const [];
  // The person's own day borders — later-today speaks their clock.
  int _rolloverHour = 0;
  int _dayStartHour = 0;
  String _todayKey = '';

  // CARE PROFILES (docs/care-profiles.md): the named doors this seat
  // holds, and which one is open.
  List<CareProfile> _profiles = const [];
  CareProfile? _sitting;

  Timer? _revisionDebounce;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _load();
    // A sync arriving underneath must paint the day — a restart-to-refresh
    // is what made receive-first look empty on the live L2 pair.
    IsarService.dataRevision.addListener(_onDataRevision);
  }

  void _onDataRevision() {
    _revisionDebounce?.cancel();
    _revisionDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _loadProfiles();
      _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _revisionDebounce?.cancel();
    IsarService.dataRevision.removeListener(_onDataRevision);
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final all = await CareProfiles.list();
    final sittingId = await CareProfiles.sittingId();
    if (!mounted) return;
    CareProfile? sitting;
    for (final p in all) {
      if (p.id == sittingId) sitting = p;
    }
    setState(() {
      _profiles = all;
      _sitting = sitting;
    });
  }

  /// Open another person's door: swap the store, repaint the day.
  Future<void> _sitWith(CareProfile p) async {
    if (_sitting?.id == p.id) return;
    await CareProfiles.enter(p);
    await _loadProfiles();
    await _load();
  }

  /// THEIR CLOCK, IN THE INSPECTOR'S HAND (owner, 2026-08-18: level 3–4
  /// "are not really feeling time the same as regular humans" — the
  /// caregiver holds the aligned day). Two fusion sheets — start, then
  /// end — written into the SITTING profile's store; the next sync round
  /// carries it, and the person's device adopts it only under full
  /// care/guided (adoptPersonDayHour — the inspector's hand, no one
  /// else's).
  Future<void> _setTheirClock() async {
    final who = _sitting?.name ?? _personName;
    final start = await showTimeFusionSheet(
      context: context,
      title: who.isEmpty
          ? L.t('When does their day start?', 'מתי היום שלהם מתחיל?')
          : L.t('When does $who\'s day start?', 'מתי היום של $who מתחיל?'),
      initial: TimeOfDay(hour: _dayStartHour == 0 ? 8 : _dayStartHour,
          minute: 0),
      quarters: false,
    );
    if (start == null || !mounted) return;
    final end = await showTimeFusionSheet(
      context: context,
      title: who.isEmpty
          ? L.t('When does their day end?', 'מתי היום שלהם נגמר?')
          : L.t('When does $who\'s day end?', 'מתי היום של $who נגמר?'),
      initial: TimeOfDay(hour: _rolloverHour, minute: 0),
      quarters: false,
      maxHour: 6,
    );
    if (end == null || !mounted) return;
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(
        s.copyWith(dayStartHour: start.hour, dayRolloverHour: end.hour));
    // HAND-DELIVERY (lived 2026-08-19 on the wake): an instruction just
    // written must ship without pulling first, or the round's receive
    // leg eats it with the person's old value.
    LanSyncService.instance.pushTrustedNow(pushOnly: true);
    await _load();
    if (!mounted) return;
    BnsSnack.show(context, SnackBar(
        content: Text(L.t(
            'Their clock is set: ${start.hour.toString().padLeft(2, '0')}:00'
            '–0${end.hour}:00. Sent to them now.',
            'השעון שלהם נקבע: ${start.hour.toString().padLeft(2, '0')}:00'
            '–0${end.hour}:00. נשלח אליהם עכשיו.'))));
  }

  /// A new named door. The name can be spoken — voice-first everywhere.
  Future<void> _newProfile() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(L.t('Who do you help?', 'את מי אתה מלווה?')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: L.t('Their name', 'השם שלהם'),
            border: const OutlineInputBorder(),
            suffixIcon: DictationMicButton(controller: ctrl),
          ),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(L.t('Cancel', 'ביטול')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: Text(L.t('Open their door', 'לפתוח להם דלת')),
          ),
        ],
      ),
    );
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) return;
    final p = await CareProfiles.create(trimmed);
    await _sitWith(p);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    // The helper watches the PERSON'S day — same owl-time border, so at
    // 01:30 the caregiver still sees tonight's list, exactly as they do.
    final settings = await IsarService.getSettings();
    final logicalDay = logicalDateOf(DateTime.now(), settings.dayRolloverHour);
    final dateStr = dayKeyOf(logicalDay);
    _rolloverHour = settings.dayRolloverHour;
    _dayStartHour = settings.dayStartHour;
    _todayKey = dateStr;

    final routines = await IsarService.getAllRoutines();
    final logs = await IsarService.getLogsForDate(dateStr);
    final captures = await IsarService.getAllCaptures();
    final events = await IsarService.getEventsForDate(dateStr);
    final trusted = await IsarService.getTrustedDevices();
    final allLogs = await IsarService.getAllCompletionLogs();

    if (!mounted) return;
    setState(() {
      _todayRoutines = routines.where((r) => r.appliesOn(logicalDay)).toList()
        ..sort(
          (a, b) => (a.timeOn(dateStr) ?? '99:99').compareTo(
            b.timeOn(dateStr) ?? '99:99',
          ),
        );
      _todayLogs = logs;
      // A helper is trusted with the hard moments too — that is the whole
      // point of level 3 ("the frustration IS the signal").
      _feed = buildDayFeed(
        date: logicalDay,
        routines: routines,
        logs: logs,
        captures: captures,
        events: events,
        includeMadVents: true,
      );
      _glance = buildCareGlance(
        now: DateTime.now(),
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
      _asks = captures.where(isAskedHelpCapture).toList()
        ..sort((a, b) => b.at.compareTo(a.at));
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
        L.t(
          'No device is paired yet — nothing here comes from them.',
          'עדיין לא מחובר אף מכשיר — שום דבר כאן לא מגיע מהם.',
        ),
        action: TextButton(
          onPressed: () => context.push('/sync'),
          child: Text(L.t('Connect', 'לחבר')),
        ),
      );
    }
    // PAIRED IS A FACT, PRESENCE IS A MOOD (caregiver report, 2026-08-16:
    // the red bar said "never connected" when the truth was "paired with
    // Ben, just not hearing a hello right now"). The banner names the
    // person and the durable state; quiet-right-now is said as quiet,
    // never as "no device was ever connected".
    final who = _personName.trim().isEmpty
        ? L.t('their device', 'המכשיר שלהם')
        : _personName.trim();
    final age = DateTime.now().difference(_lastSync!);
    if (age > const Duration(days: 3650)) {
      // Paired, but a real sync never completed yet — say that, not
      // "the picture is from 55 years ago".
      return _banner(
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        Icons.link,
        L.t(
          'Paired with $who — no sync has completed yet.',
          'מחוברים ל־$who — עוד לא הושלם סנכרון.',
        ),
      );
    }
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
          ? L.t(
              'Paired with $who — this picture is from $when, and their '
                  'device has not reached this one since.',
              'מחוברים ל־$who — התמונה הזאת מ$when, והמכשיר שלהם לא הגיע '
                  'לכאן מאז.',
            )
          : L.t(
              'Paired with $who — last heard $when.',
              'מחוברים ל־$who — נשמע לאחרונה $when.',
            ),
    );
  }

  /// The helper moves the clock; sync carries it to the person, whose own
  /// device re-registers the reminder by itself. Today only — tomorrow the
  /// usual time returns on its own.
  Future<void> _postponeTheirs(Routine r, String hhmm) async {
    await IsarService.addRoutine(r.postponeOn(_todayKey, hhmm));
    await _load();
    if (!mounted) return;
    BnsSnack.show(context, 
      SnackBar(
        content: Text(
          L.t(
            'Moved to $hhmm — today only. It will reach them.',
            'עבר ל־$hhmm — רק היום. זה יגיע אליהם.',
          ),
        ),
      ),
    );
  }

  Widget _banner(
    Color bg,
    Color fg,
    IconData icon,
    String text, {
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: fg)),
          ),
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
      BnsSnack.show(context, 
        SnackBar(
          content: Text(
            L.t(
              'That recording is not on this device.',
              'ההקלטה הזאת לא נמצאת במכשיר הזה.',
            ),
          ),
        ),
      );
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
        title: _sitting?.name.isNotEmpty == true
            ? _sitting!.name
            : L.t('Their day', 'היום שלהם'),
        actions: [
          // THE DOORS (owner, 2026-08-17: "choose from dropdown the
          // profile"). Every person this seat helps, by name, one tap —
          // and a worded door for someone new. Wrong-profile pushes are
          // impossible by structure; this is just which day is open.
          PopupMenuButton<String>(
            tooltip: L.t('Choose a person', 'לבחור אדם'),
            onSelected: (v) async {
              if (v == '_new') {
                await _newProfile();
                return;
              }
              for (final p in _profiles) {
                if (p.id == v) {
                  await _sitWith(p);
                  break;
                }
              }
            },
            itemBuilder: (c) => [
              for (final p in _profiles)
                PopupMenuItem(
                  value: p.id,
                  child: Row(
                    children: [
                      Icon(
                        p.id == _sitting?.id
                            ? Icons.meeting_room
                            : Icons.door_front_door_outlined,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(p.name),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: '_new',
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 20),
                    const SizedBox(width: 10),
                    Text(L.t('Someone new...', 'אדם חדש...')),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    L.t('People', 'אנשים'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
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
                  // Their clock, visible and settable from the seat —
                  // never a reason to send anyone to הגדרות.
                  if (_profiles.isNotEmpty)
                    ListTile(
                      leading: const Icon(Icons.alarm),
                      title: Text(L.t('Alarm for everyone', 'צלצול לכולם')),
                      subtitle: Text(L.t(
                          'Each person hears it on their own clock. This phone does not ring.',
                          'שעת צלצול לכל האנשים בליווי — מצלצל במכשיר שלהם.')),
                      onTap: () => openCareAlarmDoor(context),
                    ),
                  if (_sitting != null)
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(L.t('Their clock', 'השעון שלהם')),
                      subtitle: Text(_dayStartHour == 0 &&
                              _rolloverHour == 0
                          ? L.t('Not set — midnight to midnight',
                              'לא נקבע — מחצות עד חצות')
                          : L.t(
                              'Day starts ${_dayStartHour.toString().padLeft(2, '0')}:00 · ends 0$_rolloverHour:00',
                              'היום מתחיל ${_dayStartHour.toString().padLeft(2, '0')}:00 · נגמר 0$_rolloverHour:00')),
                      trailing: TextButton(
                        onPressed: _setTheirClock,
                        child: Text(L.t('Set', 'לקבוע')),
                      ),
                      onTap: _setTheirClock,
                    ),
                  // Building the next day is the helper's evening work
                  // (owner, 2026-08-18: tomorrow as its own entity).
                  // Opens the sitting person's Tomorrow room; what is
                  // built here reaches them on the next sync. The ✓
                  // stays theirs — this room has none.
                  if (_sitting != null)
                    ListTile(
                      leading: const Icon(Icons.wb_twilight),
                      title:
                          Text(L.t('The plan for tomorrow', 'התוכנית למחר')),
                      subtitle: Text(L.t(
                          'Build their next day from tonight — plans, hours, what to take.',
                          'לבנות להם את היום הבא מהערב — תוכניות, שעות, מה לוקחים.')),
                      onTap: () => context.push('/tomorrow'),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      L.t(
                        '$who — ${DateFormat.MMMMEEEEd().format(DateTime.now())}',
                        '$who — ${DateFormat.MMMMEEEEd().format(DateTime.now())}',
                      ),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  if (_asks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: cs.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              L.t('They asked for help', 'הם ביקשו עזרה'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              askedHelpShareLine(hebrew: L.isHebrew),
                              style: TextStyle(color: cs.onTertiaryContainer),
                            ),
                            const SizedBox(height: 8),
                            for (final a in _asks.take(6))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '• ${memoryWords(a).isEmpty ? (a.contextNote ?? '') : memoryWords(a)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // How the day is going — counted, never scored.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      L.t(
                        '${_feed?.doneCount ?? 0} done · '
                            '${_todayRoutines.length} on the list today',
                        '${_feed?.doneCount ?? 0} נעשו · '
                            '${_todayRoutines.length} ברשימה היום',
                      ),
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
                            Text(
                              L.t('Worth knowing', 'כדאי לדעת'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
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
                                  'בעיקר סביב: ${_glance!.aboutTitles.join(', ')}',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurfaceVariant,
                                ),
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
                    child: Text(
                      L.t('Their list today', 'הרשימה שלהם היום'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_todayRoutines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        L.t(
                          'Nothing on their list today. You can build it below.',
                          'אין כלום ברשימה שלהם היום. אפשר לבנות אותה למטה.',
                        ),
                      ),
                    )
                  else
                    ..._todayRoutines.map((r) {
                      final log = _logFor(r.id);
                      final done = log?.status == CompletionStatus.done;
                      final skipped = log?.status == CompletionStatus.skipped;
                      final why = (log?.reason ?? '').trim();
                      final movedToday =
                          r.timeOn(_todayKey) != r.time && r.time != null;
                      return Card(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ListTile(
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
                                  // Today's actual clock — a later-today move
                                  // shows the moved hour, not the usual one.
                                  Text(
                                    RecurrenceUtils.describe(
                                      r,
                                      dayKey: _todayKey,
                                    ),
                                  ),
                                  if (movedToday)
                                    Text(
                                      L.t(
                                        'Moved for today — usually ${r.time}',
                                        'הועבר להיום — בדרך כלל ${r.time}',
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  if (skipped)
                                    Text(
                                      why.isEmpty
                                          ? L.t(
                                              'Didn\'t happen — no reason kept',
                                              'לא קרה — לא נשמרה סיבה',
                                            )
                                          : L.t(
                                              'Didn\'t happen — “$why”',
                                              'לא קרה — ״$why״',
                                            ),
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: cs.tertiary,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: (skipped && why.isNotEmpty)
                                  ? _speak(why)
                                  : null,
                            ),
                            // THE INSPECTOR MOVES THE CLOCK (tester, 2026-08-16:
                            // "in the L4 pair nobody can postpone"). Day-building
                            // stays the helper's hand; the ✓ stays the person's.
                            if (!done && !skipped && r.time != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  10,
                                ),
                                child: LaterTodayDoor(
                                  now: DateTime.now(),
                                  rolloverHour: _rolloverHour,
                                  startHour: _dayStartHour,
                                  onPicked: (hhmm) => _postponeTheirs(r, hhmm),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),

                  // Their own words today — the reason this app exists.
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      L.t('What they told today', 'מה הם סיפרו היום'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final said = (_feed?.items ?? [])
                          .where(
                            (i) =>
                                i.kind == DayFeedKind.needHelp ||
                                i.kind == DayFeedKind.diary ||
                                i.kind == DayFeedKind.thought ||
                                i.kind == DayFeedKind.madVent,
                          )
                          .toList();
                      if (said.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            L.t(
                              'Nothing said yet today.',
                              'עדיין לא נאמר כלום היום.',
                            ),
                          ),
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
                                color:
                                    i.kind == DayFeedKind.needHelp ||
                                        i.kind == DayFeedKind.madVent
                                    ? cs.tertiary
                                    : null,
                              ),
                              title: Text(
                                i.hasWords
                                    ? i.words!
                                    : L.t(
                                        'A voice-only moment (no words yet)',
                                        'רגע קולי בלבד (עדיין בלי מילים)',
                                      ),
                              ),
                              subtitle: Text(
                                '${DateFormat.Hm().format(i.at)}  ·  ${i.headline}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (i.hasWords) _speak(i.words!),
                                  if (i.hasAudio)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.play_circle_filled,
                                        size: 28,
                                      ),
                                      tooltip: L.t(
                                        'Hear their voice',
                                        'לשמוע את הקול שלהם',
                                      ),
                                      onPressed: () => _play(i.audioPath!),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  // The helper's doors: build the day, read the whole thread.
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.push('/routines'),
                          icon: const Icon(Icons.list_alt),
                          label: Text(
                            L.t('Build their day', 'לבנות את היום שלהם'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/day'),
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(
                            L.t('Read the whole day', 'לקרוא את כל היום'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => context.push('/calendar'),
                          icon: const Icon(Icons.event_note),
                          label: Text(
                            L.t('Appointments & plans', 'פגישות ותוכניות'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => context.push('/sync'),
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(
                            L.t('Connection & settings', 'חיבור והגדרות'),
                          ),
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
