import 'package:flutter/material.dart';

import 'package:bns/core/care_alarm.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/owl_time.dart';
import 'package:bns/data/local/care_profiles.dart';
import 'package:bns/data/sync/lan_sync_service.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/time_fusion_picker.dart';
import 'package:bns/ui/snack.dart';

/// One door on the Care home: set a ring for every person this seat
/// helps. The helper sees the times; their pocket stays quiet.
Future<void> openCareAlarmDoor(BuildContext context) async {
  final seats = await CareProfiles.alarmSeats();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CareAlarmSheet(seats: seats),
  );
}

class _CareAlarmSheet extends StatefulWidget {
  final List<CareAlarmSeat> seats;

  const _CareAlarmSheet({required this.seats});

  @override
  State<_CareAlarmSheet> createState() => _CareAlarmSheetState();
}

class _CareAlarmSheetState extends State<_CareAlarmSheet> {
  String _hhmm = '';
  bool _sending = false;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController();
    for (final s in widget.seats) {
      if (s.wakeTime.isNotEmpty) {
        _hhmm = s.wakeTime;
        _note.text = s.wakeNote;
        break;
      }
    }
    if (_hhmm.isEmpty) _hhmm = '08:00';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final parsed = parseHhmm(_hhmm);
    final t = await showTimeFusionSheet(
      context: context,
      title: L.t('When should it ring for them?', 'מתי שיצלצל אצלם?'),
      initial: parsed == null
          ? const TimeOfDay(hour: 8, minute: 0)
          : TimeOfDay(hour: parsed.hour, minute: parsed.minute),
    );
    if (t == null) return;
    setState(() {
      _hhmm = '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _send() async {
    if (_sending || widget.seats.isEmpty) return;
    setState(() => _sending = true);
    final sittingId = await CareProfiles.sittingId();
    final all = await CareProfiles.list();
    await CareProfiles.writeWakeToAll(
      time: _hhmm,
      note: _note.text.trim(),
    );
    // Each door pushes from ITS store. Trust reloads on enter
    // (afterSit) so Dana's day cannot address Yossi's phone.
    // HAND-DELIVERY (lived 2026-08-19): push WITHOUT pulling first —
    // the round's receive-first leg was eating the fresh time with the
    // person's old one before the send leg ever ran.
    for (final p in all) {
      await CareProfiles.enter(p);
      LanSyncService.instance.pushTrustedNow(pushOnly: true);
    }
    if (sittingId != null) {
      for (final p in all) {
        if (p.id == sittingId) {
          await CareProfiles.enter(p);
          break;
        }
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    BnsSnack.show(context, SnackBar(
      content: Text(L.t(
        'Sent. It reaches them on the next sync.',
        'נשלח. יגיע אליהם בסנכרון.',
      )),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.t('Alarm for everyone', 'צלצול לכולם'),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                L.t(
                  'Set here, rings on their device. This device stays quiet.',
                  'נקבע כאן ומצלצל במכשיר שלהם. המכשיר הזה נשאר שקט.',
                ),
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _sending ? null : _pickTime,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(L.t('Ring at $_hhmm', 'צלצול ב־$_hhmm')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !_sending,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: L.t(
                    'Words the ring carries (optional)',
                    'טקסט שיוצג בצלצול (רשות)',
                  ),
                  border: const OutlineInputBorder(),
                  suffixIcon: DictationMicButton(controller: _note),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                L.t('Where it rings', 'אצל מי יצלצל'),
                style: text.titleMedium,
              ),
              const SizedBox(height: 6),
              if (widget.seats.isEmpty)
                Text(
                  L.t(
                    'No one behind a door yet.',
                    'עדיין אין אף אחד מאחורי דלת.',
                  ),
                )
              else
                for (final seat in widget.seats) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          careAlarmSeatLine(
                            seat: seat,
                            sentTime: _hhmm,
                            t: L.t,
                          ),
                          style: text.bodyLarge,
                        ),
                        if (careAlarmDayStartLine(seat: seat, t: L.t)
                            case final start?)
                          Text(
                            start,
                            style: text.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _sending || widget.seats.isEmpty ? null : _send,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(_sending
                    ? L.t('Sending…', 'שולחים…')
                    : L.t('Send', 'לשלוח')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(L.t('Close', 'סגירה')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
