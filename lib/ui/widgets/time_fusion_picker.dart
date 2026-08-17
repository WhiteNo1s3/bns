import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';

/// THE TIME, WITHOUT THE WALL (owner, 2026-08-18: "it states all the
/// times... less nightmare to look at a long list listing each time in
/// 15 minutes interval" — asked as "a fusion of our extra-15-minutes
/// wonderful UI and the time on the side to scroll").
///
/// One sheet: the chosen time stands BIG in the middle; beside it a
/// quiet hour rail to scroll and tap for the big jumps; under it the
/// postpone-style «15 דקות» buttons for the fine step; one confirm door
/// wearing the time it will set. Nothing moves on its own (static law);
/// nothing lists ninety-six rows.
///
/// [quarters] false = whole hours only (day start / day end) — the rail
/// alone picks, the ±15 row stays home.
Future<TimeOfDay?> showTimeFusionSheet({
  required BuildContext context,
  required String title,
  TimeOfDay? initial,
  bool quarters = true,
  int maxHour = 23,
  double textScale = 1.0,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimeFusionSheet(
      title: title,
      initial: initial ?? const TimeOfDay(hour: 10, minute: 0),
      quarters: quarters,
      maxHour: maxHour,
      textScale: textScale,
    ),
  );
}

class _TimeFusionSheet extends StatefulWidget {
  final String title;
  final TimeOfDay initial;
  final bool quarters;
  final int maxHour;
  final double textScale;

  const _TimeFusionSheet({
    required this.title,
    required this.initial,
    required this.quarters,
    required this.maxHour,
    required this.textScale,
  });

  @override
  State<_TimeFusionSheet> createState() => _TimeFusionSheetState();
}

class _TimeFusionSheetState extends State<_TimeFusionSheet> {
  static const double _rowHeight = 52;

  late int _hour;
  late int _minute;
  late final ScrollController _rail;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour.clamp(0, widget.maxHour);
    _minute = widget.quarters ? (widget.initial.minute ~/ 15) * 15 : 0;
    // Land with the chosen hour in view — a JUMP at build, never a glide.
    final target = (_hour - 2).clamp(0, widget.maxHour) * _rowHeight;
    _rail = ScrollController(initialScrollOffset: target);
  }

  @override
  void dispose() {
    _rail.dispose();
    super.dispose();
  }

  String get _shown =>
      '${_hour.toString().padLeft(2, '0')}:${_minute.toString().padLeft(2, '0')}';

  void _nudge(int minutes) {
    setState(() {
      var total = (_hour * 60 + _minute + minutes) % (24 * 60);
      if (total < 0) total += 24 * 60;
      _hour = (total ~/ 60).clamp(0, widget.maxHour);
      _minute = total % 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scale = widget.textScale;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The hour rail — scrolled by the hand that reads it.
            SizedBox(
              width: 92 * scale,
              height: 5 * _rowHeight,
              child: ListView.builder(
                controller: _rail,
                itemExtent: _rowHeight,
                itemCount: widget.maxHour + 1,
                itemBuilder: (c, h) {
                  final on = h == _hour;
                  return InkWell(
                    onTap: () => setState(() => _hour = h),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: on
                          ? BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(12),
                            )
                          : null,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(
                          fontSize: 18 * scale,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? cs.primary : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 20),
            // The time itself, big; the gentle steps; the one door out.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 16 * scale,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Text(
                    _shown,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 44 * scale,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (widget.quarters) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _nudge(-15),
                            style: FilledButton.styleFrom(
                                minimumSize: Size(96 * scale, 64 * scale)),
                            child: Text('−15 ${L.t('min', 'דק׳')}',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                    fontSize: 18 * scale,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () => _nudge(15),
                            style: FilledButton.styleFrom(
                                minimumSize: Size(96 * scale, 64 * scale)),
                            child: Text('+15 ${L.t('min', 'דק׳')}',
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                    fontSize: 18 * scale,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                        context, TimeOfDay(hour: _hour, minute: _minute)),
                    style: FilledButton.styleFrom(
                        minimumSize: Size.fromHeight(56 * scale)),
                    child: Text('${L.t('Set', 'לקבוע')} — $_shown',
                        style: TextStyle(fontSize: 17 * scale)),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(48, 44)),
                      child: Text(L.t('Close', 'סגירה')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
