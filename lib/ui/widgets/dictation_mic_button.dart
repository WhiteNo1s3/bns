import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/stt_service.dart';

/// A small mic that dictates straight into a [TextEditingController] —
/// the "STT all the time" building block. Drop it as a `suffixIcon` (or
/// anywhere) next to ANY text field and the field becomes voice-writable.
///
/// Behavior:
/// - Tap: start continuous dictation (device engine, keeps restarting itself
///   through pauses). Tap again: stop.
/// - Words land live at the end of whatever is already typed — dictation
///   appends, never overwrites.
/// - Respects Settings.sttEnabled + sttLocale.
/// - On devices with no engine, it simply reports "voice typing isn't
///   available" once — typing always works, never a dead end.
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

class _DictationMicButtonState extends State<DictationMicButton> {
  bool _dictating = false;
  SttState _state = SttState.idle;

  /// The field's content when dictation started — dictated words append here.
  String _baseText = '';

  @override
  void dispose() {
    if (_dictating) SttService.stop();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_dictating) {
      await SttService.stop();
      if (mounted) setState(() => _dictating = false);
      return;
    }

    final settings = await IsarService.getSettings();
    if (!settings.sttEnabled) return;

    final mic = await Permission.microphone.request();
    if (mic != PermissionStatus.granted) {
      _tellOnce('Voice typing needs the microphone. Typing works as always.');
      return;
    }

    _baseText = widget.controller.text;
    final started = await SttService.start(
      localeId: settings.sttLocale,
      onText: (text) {
        if (!mounted) return;
        final sep =
            _baseText.isEmpty || _baseText.endsWith(' ') || text.isEmpty
                ? ''
                : ' ';
        widget.controller.text = '$_baseText$sep$text';
        widget.controller.selection = TextSelection.collapsed(
            offset: widget.controller.text.length);
      },
      onState: (s) {
        if (!mounted) return;
        setState(() {
          _state = s;
          if (s == SttState.unavailable || s == SttState.idle) {
            _dictating = false;
          }
        });
        if (s == SttState.unavailable) {
          _tellOnce(
              'Voice typing is not available right now. Typing works as always.');
        }
      },
    );

    if (mounted) setState(() => _dictating = started);
    if (!started) {
      _tellOnce(
          'Voice typing is not available on this device. Typing works as always.');
    }
  }

  static bool _told = false;
  void _tellOnce(String msg) {
    if (_told || !mounted) return;
    _told = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final color = _dictating
        ? (_state == SttState.restarting
            ? Colors.orange
            : Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      iconSize: widget.dense ? 22 : 28,
      tooltip: _dictating ? 'Stop voice typing' : 'Voice typing (speak to write)',
      icon: Icon(_dictating ? Icons.mic : Icons.mic_none_rounded, color: color),
      onPressed: _toggle,
    );
  }
}
