import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/speech_popup.dart';
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

    // Every failed attempt says WHY, once per attempt — a silent mic that
    // does nothing reads as "broken", never as "disabled in settings".
    _told = false;

    final settings = await IsarService.getSettings();
    if (!settings.sttEnabled) {
      _tellOnce(L.t(
          'Voice typing is turned off in Settings (the Sync screen). '
          'Typing works as always.',
          'הקלדה קולית כבויה בהגדרות (מסך הסנכרון). '
          'הקלדה רגילה עובדת כמו תמיד.'));
      return;
    }

    // permission_handler is not on macOS — calling it killed the tap
    // and the system never asked. On Mac the speech engine asks itself.
    if (!Platform.isMacOS && !Platform.isLinux) {
      try {
        final mic = await Permission.microphone.request();
        if (mic != PermissionStatus.granted) {
          _tellOnce(L.t(
              'Voice typing needs the microphone. Typing works as always.',
              'הקלדה קולית צריכה את המיקרופון. הקלדה רגילה עובדת כמו תמיד.'));
          return;
        }
      } catch (_) {}
    }

    _baseText = widget.controller.text;

    // THE WAZE DOOR FIRST for Hebrew (owner's phone, 2026-07-26): the
    // embedded engine refuses he_IL/iw_IL on this device, while the system
    // popup — Waze's own door — hears Hebrew perfectly. Try it; only fall
    // through to the embedded engine if the door itself isn't there.
    final wantHebrew = _wantsHebrew(settings.sttLocale);
    if (wantHebrew && SpeechPopup.isSupported) {
      if (mounted) setState(() => _dictating = true);
      final words = await SpeechPopup.recognize(
        locale: settings.sttLocale.trim().isEmpty
            ? 'he-IL'
            : settings.sttLocale.trim().replaceAll('_', '-'),
        prompt: L.t('Speak now', 'אפשר לדבר עכשיו'),
      );
      if (mounted) setState(() => _dictating = false);
      if (words != null) {
        // Door answered (words, or empty when cancelled) — respect it.
        final text = words.trim();
        if (text.isNotEmpty) {
          final sep = _baseText.isEmpty || _baseText.endsWith(' ') ? '' : ' ';
          widget.controller.text = '$_baseText$sep$text';
          widget.controller.selection = TextSelection.collapsed(
              offset: widget.controller.text.length);
        }
        return;
      }
      // Door missing on this device — fall through to the engine below.
    }

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
          _tellUnavailable(L.t(
              'Voice typing is not available right now. Typing works as always.',
              'הקלדה קולית לא זמינה כרגע. הקלדה רגילה עובדת כמו תמיד.'));
        }
      },
    );

    if (mounted) setState(() => _dictating = started);
    if (!started) {
      _tellUnavailable(L.t(
          'Voice typing is not available on this device. Typing works as always.',
          'הקלדה קולית לא זמינה במכשיר הזה. הקלדה רגילה עובדת כמו תמיד.'));
    }
  }

  /// Hebrew is wanted when explicitly chosen, or when the app itself is
  /// Hebrew and no other language was picked.
  static bool _wantsHebrew(String sttLocale) {
    final chosen = sttLocale.trim().toLowerCase();
    if (chosen.isEmpty) return L.isHebrew;
    return chosen.startsWith('he') || chosen.startsWith('iw');
  }

  /// Unavailable is not always the same story. When the engine said WHY —
  /// a missing language pack — say THAT, gently, instead of a vague shrug.
  void _tellUnavailable(String fallback) {
    final err = SttService.lastErrorMsg ?? '';
    if (err.contains('language')) {
      _tellOnce(L.t(
          "The phone's speech engine doesn't have Hebrew installed. "
          "You can add it in the phone's Google voice-typing settings — "
          "meanwhile the mic uses the phone's language.",
          'נראה שמנוע הדיבור של הטלפון לא כולל עברית. '
          'אפשר להוסיף אותה בהגדרות ההקלדה הקולית של Google — '
          'בינתיים המיקרופון ישתמש בשפת הטלפון.'));
      return;
    }
    _tellOnce(fallback);
  }

  /// Once per ATTEMPT (reset in [_toggle]) — not once per app lifetime,
  /// which made every later failure completely silent.
  static bool _told = false;
  void _tellOnce(String msg) {
    if (_told || !mounted) return;
    _told = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // A mic that cannot listen is worse than no mic — on desktops without
    // live dictation the words come from recording instead (owner's law:
    // as little confusion as possible).
    if (!SttService.isSupportedPlatform) return const SizedBox.shrink();
    final color = _dictating
        ? (_state == SttState.restarting
            ? Colors.orange
            : Theme.of(context).colorScheme.primary)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return IconButton(
      iconSize: widget.dense ? 22 : 28,
      tooltip: _dictating
          ? L.t('Stop voice typing', 'לעצור הקלדה קולית')
          : L.t('Voice typing (speak to write)',
              'הקלדה קולית (מדברים — וזה נכתב)'),
      icon: Icon(_dictating ? Icons.mic : Icons.mic_none_rounded, color: color),
      onPressed: _toggle,
    );
  }
}
