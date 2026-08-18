import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:go_router/go_router.dart';

import 'package:bns/core/day_items.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/wake/wake_controls.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// THE ALARM PAGE (owner, 2026-08-19: "its not only to wake up, its to
/// set real clock to alarm... wire the list to the alarm page, let user
/// add alarm from the hip but also shows the day, and if you press on a
/// mission we shall present him with settings — everyday? in selected
/// days? single time alarm? — and then implement this into the clock").
///
/// One room: the wake at the top; below it WHAT IS LEFT TODAY — the
/// unanswered missions in the person's order, each one tap away from
/// becoming a REAL ring in the phone's own clock (once / every day /
/// chosen days); and a free alarm "from the hip". The phone's clock is
/// the breach into the OS: BNS is not hooked into any system, so the
/// things that must tick are planted where ticking cannot die — and the
/// nudge wears the person's own hand, not a warden's.
class WakeScreen extends StatefulWidget {
  const WakeScreen({super.key});

  @override
  State<WakeScreen> createState() => _WakeScreenState();
}

class _WakeScreenState extends State<WakeScreen> {
  bool _loading = true;
  bool _caregiver = false;
  bool _guided = false;
  int _rollover = 0;
  int _startHour = 0;
  String _todayKey = '';
  List<Object> _left = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await IsarService.getSettings();
    _caregiver = s.caregiverDevice;
    _guided = s.guidedMode;
    _rollover = s.dayRolloverHour;
    _startHour = s.dayStartHour;
    final now = DateTime.now();
    final today = logicalDateOf(now, _rollover);
    _todayKey = dayKeyOf(today);
    if (!_caregiver && !_guided) {
      final all = await IsarService.getAllRoutines();
      final routines =
          all.where((r) => r.appliesOn(today) && r.isActive).toList();
      final plans = await IsarService.getEventsForDate(_todayKey);
      final logs = await IsarService.getLogsForDate(_todayKey);
      final done = <String>{}, skipped = <String>{};
      for (final l in logs) {
        (l.status == CompletionStatus.done ? done : skipped).add(l.routineId);
      }
      _left = openDayItemsInNextOrder(
        routines: routines,
        plans: plans,
        doneRoutineIds: done,
        skippedRoutineIds: skipped,
        now: now,
        rolloverHour: _rollover,
        startHour: _startHour,
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  /// A mission becomes a real ring: pick the repeat, then the phone's
  /// clock opens pre-filled — the person saves it there, song and all.
  Future<void> _missionToAlarm(Object item) async {
    final title = dayItemTitle(item);
    var hhmm = dayItemTime(item, dayKey: _todayKey);
    if (hhmm == null) {
      final t = await showTimeFusionSheet(
        context: context,
        title: L.t('When should it ring?', 'מתי שיצלצל?'),
        initial: nextQuarterFrom(DateTime.now()),
      );
      if (t == null) return;
      hhmm = '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    }
    if (!mounted) return;
    await _repeatSheet(title, hhmm);
  }

  /// From the hip: an alarm that is not a mission — a time and a ring.
  Future<void> _freeAlarm() async {
    final t = await showTimeFusionSheet(
      context: context,
      title: L.t('An alarm — what time?', 'צלצול — באיזו שעה?'),
      initial: nextQuarterFrom(DateTime.now()),
    );
    if (t == null || !mounted) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    await _repeatSheet(L.t('BNS alarm', 'צלצול BNS'), hhmm);
  }

  /// everyday? selected days? single time? — then into the clock.
  Future<void> _repeatSheet(String title, String hhmm) async {
    // java.util.Calendar days: 1=Sunday .. 7=Saturday.
    final picked = <int>{};
    const dayLetters = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$title — $hhmm',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _plant(title, hhmm, null);
                  },
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(L.t('One time', 'פעם אחת')),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _plant(title, hhmm, const [1, 2, 3, 4, 5, 6, 7]);
                  },
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(L.t('Every day', 'כל יום')),
                ),
                const SizedBox(height: 14),
                Text(L.t('Or on chosen days:', 'או בימים מסוימים:'),
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(dayLetters[d - 1],
                            style: const TextStyle(fontSize: 16)),
                        selected: picked.contains(d),
                        onSelected: (on) => setSheet(
                            () => on ? picked.add(d) : picked.remove(d)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: picked.isEmpty
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _plant(title, hhmm, picked.toList()..sort());
                        },
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: Text(L.t('Set on these days', 'לקבוע בימים שסימנתי')),
                ),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 44)),
                    child: Text(L.t('Close', 'סגירה')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _plant(String label, String hhmm, List<int>? days) async {
    final p = parseHhmm(hhmm);
    if (p == null) return;
    bool ok = false;
    try {
      ok = await const MethodChannel('bns/wake_clock').invokeMethod('plant', {
            'hour': p.hour,
            'minutes': p.minute,
            'message': 'BNS · $label',
            if (days != null) 'days': days,
          }) ==
          true;
    } catch (_) {}
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t('No clock app answered on this device.',
              'שעון הטלפון לא נענה במכשיר הזה.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: BnsAppBar(title: L.t('Alarm clock', 'שעון מעורר')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const WakeControls(showSeatLine: true),
                  if (!_caregiver && !_guided) ...[
                    const SizedBox(height: 24),
                    Text(L.t('What is left today', 'מה נשאר היום'),
                        style: text.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                        Platform.isAndroid
                            ? L.t(
                                'A tap on a mission makes it a real ring in the '
                                'phone\'s own clock — once, every day, or on '
                                'chosen days.',
                                'נגיעה במשימה הופכת אותה לצלצול אמיתי בשעון של '
                                'הטלפון — פעם אחת, כל יום, או בימים שתבחרו.')
                            : L.t('Today\'s open missions, in order.',
                                'המשימות הפתוחות של היום, לפי הסדר.'),
                        style: text.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    if (_left.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            L.t('Everything is answered. The day is clear. 🌿',
                                'הכול נענה. היום נקי. 🌿'),
                            style: text.bodyMedium),
                      )
                    else
                      ..._left.map((item) {
                        final hhmm =
                            dayItemTime(item, dayKey: _todayKey);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: Platform.isAndroid
                                ? () => _missionToAlarm(item)
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(hhmm ?? '—',
                                        textDirection: TextDirection.ltr,
                                        style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: hhmm == null
                                                ? cs.onSurfaceVariant
                                                : cs.primary)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(dayItemTitle(item),
                                        style: text.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  if (Platform.isAndroid)
                                    Icon(Icons.alarm_add,
                                        size: 22, color: cs.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    if (Platform.isAndroid) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _freeAlarm,
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48)),
                        icon: const Icon(Icons.more_time, size: 20),
                        label: Text(L.t('A free alarm — pick a time',
                            'צלצול חופשי — לבחור שעה')),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
      // The no-dead-end guarantee: a pinned worded way back, every width.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.tonal(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              context.go('/');
            }
          },
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child:
              Text(L.t('Back', 'חזרה'), style: const TextStyle(fontSize: 17)),
        ),
      ),
    );
  }
}
