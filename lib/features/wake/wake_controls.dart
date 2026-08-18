import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/core/wake_words.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/notifications_service.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';

/// THE WAKE, WHEREVER ITS DOOR IS (owner, 2026-08-19: "it can be its own
/// button... whatever you see fits"). One implementation of the wake —
/// state line, set/change, plant-into-the-phone's-clock, turn off —
/// mounted in the Tomorrow room and in the wake room alike, so the two
/// doors can never drift apart.
///
/// On a Care seat there is nothing to press: the wake rings on the
/// PERSON'S nightstand, set on their device. [showSeatLine] rooms say
/// that in words; embedded uses simply render nothing (the host room
/// already gates).
class WakeControls extends StatefulWidget {
  final bool showSeatLine;
  final bool showTitle;

  const WakeControls(
      {super.key, this.showSeatLine = false, this.showTitle = true});

  @override
  State<WakeControls> createState() => _WakeControlsState();
}

class _WakeControlsState extends State<WakeControls> {
  bool _loading = true;
  bool _caregiver = false;
  bool _guided = false;
  String _wakeTime = '';
  List<Routine> _routines = const [];
  List<CalendarEvent> _events = const [];
  int _rollover = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await IsarService.getSettings();
    _caregiver = s.caregiverDevice;
    _guided = s.guidedMode;
    _wakeTime = s.wakeAlarmTime;
    _rollover = s.dayRolloverHour;
    _routines = await IsarService.getAllRoutines();
    _events = await IsarService.getAllEvents();
    if (mounted) setState(() => _loading = false);
  }

  /// The day the next ring will open — today when the hour is still
  /// ahead, otherwise tomorrow (the service computes the same).
  DateTime get _ringDay {
    final now = DateTime.now();
    final p = parseHhmm(_wakeTime);
    if (p != null) {
      var fire = DateTime(now.year, now.month, now.day, p.hour, p.minute);
      if (!fire.isAfter(now)) fire = fire.add(const Duration(days: 1));
      return logicalDateOf(fire, _rollover);
    }
    return logicalDateOf(now, _rollover).add(const Duration(days: 1));
  }

  String get _preview => wakeBodyFor(
      routines: _routines,
      events: _events,
      day: _ringDay,
      rolloverHour: _rollover,
      t: L.t);

  Future<void> _setWake() async {
    final parsed = parseHhmm(_wakeTime);
    final t = await showTimeFusionSheet(
      context: context,
      title: L.t('When do you wake tomorrow?', 'מתי מתעוררים מחר?'),
      initial: parsed == null
          ? const TimeOfDay(hour: 7, minute: 30)
          : TimeOfDay(hour: parsed.hour, minute: parsed.minute),
    );
    if (t == null) return;
    final hhmm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(wakeAlarmTime: hhmm));
    await NotificationsService.rescheduleAll(force: true);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t('The wake is set — $hhmm, every day.',
            'ההשכמה נקבעה — $hhmm, כל יום.'))));
  }

  Future<void> _clearWake() async {
    final s = await IsarService.getSettings();
    await IsarService.updateSettings(s.copyWith(wakeAlarmTime: ''));
    await NotificationsService.rescheduleAll(force: true);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('The wake is off.', 'ההשכמה כבויה.'))));
  }

  /// Hands the wake to the phone's own clock — pre-filled, the reason as
  /// its label. The clock opens so the person sees it land and can pick
  /// the song they like there; a clock alarm survives everything.
  Future<void> _plantInClock() async {
    final parsed = parseHhmm(_wakeTime);
    if (parsed == null) return;
    bool ok = false;
    try {
      ok = await const MethodChannel('bns/wake_clock').invokeMethod('plant', {
            'hour': parsed.hour,
            'minutes': parsed.minute,
            'message': 'BNS · $_preview',
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
    if (_loading) return const SizedBox(height: 48);
    if (_caregiver) {
      return widget.showSeatLine
          ? Text(
              L.t(
                  'The wake lives with them — it is set on the person\'s own device, '
                  'and rings on their nightstand.',
                  'ההשכמה גרה אצלם — היא נקבעת במכשיר של האדם עצמו, ומצלצלת ליד המיטה שלו.'),
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          : const SizedBox.shrink();
    }
    if (_guided) {
      return widget.showSeatLine
          ? Text(L.t('The morning is taken care of for you. 💚',
              'הבוקר מסודר בשבילך. 💚'))
          : const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showTitle) ...[
          Text(L.t('The wake', 'השכמה'), style: text.titleMedium),
          const SizedBox(height: 4),
        ],
        Text(
            _wakeTime.isEmpty
                ? L.t(
                    'A morning that starts with a reason. The ring '
                    'carries what waits for you.',
                    'בוקר שמתחיל עם סיבה. הצלצול נושא את מה שמחכה לך.')
                : L.t('The ring will carry: $_preview',
                    'הצלצול יישא: $_preview'),
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _setWake,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.alarm, size: 20),
          label: Text(_wakeTime.isEmpty
              ? L.t('Set a wake time', 'לקבוע שעת השכמה')
              : L.t('Wake — $_wakeTime, every day',
                  'השכמה — $_wakeTime, כל יום')),
        ),
        if (_wakeTime.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (Platform.isAndroid)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _plantInClock,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44)),
                    child: Text(
                        L.t('Put it in the phone\'s clock too',
                            'לשתול גם בשעון של הטלפון'),
                        style: const TextStyle(fontSize: 13.5)),
                  ),
                ),
              if (Platform.isAndroid) const SizedBox(width: 8),
              TextButton(
                onPressed: _clearWake,
                style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
                child: Text(L.t('Turn off', 'לכבות'),
                    style:
                        TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
