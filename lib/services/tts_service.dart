import 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

/// Speaks short prompts with the DEVICE speech engine — free, on-device,
/// no cloud AI, no subscriptions (owner rule: "not worth 1$").
///
/// One job: when a home-widget 🎤 tap opens the app already recording, the
/// phone gently says the subject prompt first ("Tell me about today") so the
/// person knows the mic is theirs. Ported from the reference-inbox idea
/// (tts_service.dart, 2026-07-06 wave), hardened: awaits completion so the
/// spoken prompt never bleeds into the recording, and stays silent in quiet
/// mode or on any engine failure.
class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _configured = false;

  /// Speak [subject] and only return once the engine finished talking
  /// (so callers can start the mic right after without recording the prompt).
  static Future<void> speakSubject(String subject) async {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) return;
    try {
      if (!_configured) {
        await _tts.awaitSpeakCompletion(true);
        await _tts.setSpeechRate(0.5); // unhurried, low cognitive load
        _configured = true;
      }
      await _tts.speak(subject);
    } catch (_) {
      // Silence is fine — the prompt is a courtesy, never a blocker.
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
