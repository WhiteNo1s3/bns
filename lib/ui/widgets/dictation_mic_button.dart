import 'dart:async';

import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/ear.dart';
import 'package:bns/services/voice_take.dart';
import 'package:bns/ui/snack.dart';

/// A mic beside any text field: press once and speak, press again and the
/// words are written. Drop it as a `suffixIcon` (or anywhere) next to ANY
/// controller and that field becomes voice-writable.
///
/// THE PRESS THAT SURVIVES A FINGER (owner, 2026-08-19: "we find a way to
/// sst less fragile than android simple one that cancel itself when you
/// press any point of the screen"). This button no longer opens the system
/// listening popup, and no longer runs a live engine that gives up after a
/// pause. It RECORDS — a plain take, held by [VoiceTake] — and then reads
/// the words off the finished file with [Ear]. Consequences, all of them
/// the point:
/// - Touching the screen, scrolling, the keyboard opening, a notification
///   landing: none of it stops the take. Only the second press does.
/// - Long thoughts are fine. There is no pause timeout to race.
/// - The words arrive a moment AFTER the press, not while speaking — so the
///   button says «כותבים…» while the ear reads, and never lies about it.
/// - Nothing is lost to a missing engine: a take nobody could read says so
///   plainly, and typing always works.
class DictationMicButton extends StatefulWidget {
  final TextEditingController controller;

  /// Compact icon-only look for `suffixIcon` slots.
  final bool dense;

  const DictationMicButton({
    super.key,
    required this.controller,
    this.dense = true,
  });

  @override
  State<DictationMicButton> createState() => _DictationMicButtonState();
}

enum _MicPhase { idle, recording, hearing }

class _DictationMicButtonState extends State<DictationMicButton> {
  _MicPhase _phase = _MicPhase.idle;
  Duration _elapsed = Duration.zero;
  Timer? _tick;

  /// Whether ANY ear can answer on this device. A mic that cannot listen is
  /// worse than no mic, so the button hides itself until one exists. Asked
  /// per mount, not once per app: the person may have just installed the
  /// offline ear, and the mic must appear without restarting anything.
  late final Future<bool> _earCheck = Ear.hasAnyEar;

  @override
  void dispose() {
    _tick?.cancel();
    // The person left mid-take: the mic must not stay open for the next
    // screen, and a half-said sentence is not kept behind their back.
    if (_phase == _MicPhase.recording) VoiceTake.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_phase == _MicPhase.hearing) return; // the ear is reading; let it
    if (_phase == _MicPhase.recording) {
      await _finish();
      return;
    }

    // Every refusal says WHY, once per attempt — a silent mic that does
    // nothing reads as "broken", never as "turned off in settings".
    final settings = await IsarService.getSettings();
    if (!settings.sttEnabled) {
      _tell(
        L.t(
          'Voice typing is turned off in Settings (the Sync screen). '
              'Typing works as always.',
          'הקלדה קולית כבויה בהגדרות (מסך הסנכרון). '
              'הקלדה רגילה עובדת כמו תמיד.',
        ),
      );
      return;
    }
    if (VoiceTake.isRecording) {
      _tell(
        L.t('Something else is already recording.', 'משהו אחר כבר מקליט כרגע.'),
      );
      return;
    }

    final started = await VoiceTake.start(
      holder: 'field',
      dir: await VoiceTake.scratchDir(),
      prefix: 'say',
    );
    if (!mounted) return;
    if (started == null) {
      _tell(
        L.t(
          'The microphone did not open. You can write it instead.',
          'המיקרופון לא נפתח. אפשר לכתוב במקום.',
        ),
      );
      return;
    }
    setState(() {
      _phase = _MicPhase.recording;
      _elapsed = Duration.zero;
    });
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = VoiceTake.elapsed);
    });
  }

  Future<void> _finish() async {
    _tick?.cancel();
    final path = await VoiceTake.stop();
    if (!mounted) return;
    setState(() => _phase = _MicPhase.hearing);
    final heard = (await Ear.hear(path ?? '')).trim();
    await VoiceTake.discard(path);
    if (!mounted) return;
    setState(() => _phase = _MicPhase.idle);
    if (heard.isEmpty) {
      _tell(
        L.t(
          'No words came back from that one. You can write it instead.',
          'לא חזרו מילים מההקלטה הזאת. אפשר לכתוב במקום.',
        ),
      );
      return;
    }
    // Dictation APPENDS, never overwrites — the field may already hold
    // something the person typed.
    final base = widget.controller.text;
    final sep = base.isEmpty || base.endsWith(' ') || base.endsWith('\n')
        ? ''
        : ' ';
    widget.controller.text = '$base$sep$heard';
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  void _tell(String msg) {
    if (!mounted) return;
    BnsSnack.show(context, SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _earCheck,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final size = widget.dense ? 22.0 : 28.0;
        switch (_phase) {
          case _MicPhase.hearing:
            return Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.primary,
                ),
              ),
            );
          case _MicPhase.recording:
            final secs = _elapsed.inSeconds;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (secs > 0)
                  Text(
                    '$secs${L.t('s', 'ש')}',
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  ),
                IconButton(
                  iconSize: size,
                  tooltip: L.t(
                    'Stop and write the words',
                    'לעצור ולכתוב את המילים',
                  ),
                  icon: Icon(Icons.stop_circle_rounded, color: scheme.error),
                  onPressed: _toggle,
                ),
              ],
            );
          case _MicPhase.idle:
            return IconButton(
              iconSize: size,
              tooltip: L.t('Speak instead of typing', 'לדבר במקום להקליד'),
              icon: Icon(
                Icons.mic_none_rounded,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: _toggle,
            );
        }
      },
    );
  }
}
