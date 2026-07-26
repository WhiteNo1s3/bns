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

  /// The OS bridge (owner, 2026-07-26: "provide those bridges to the OS,
  /// for all existing OS"): flutter_tts reaches the device voices on
  /// Android, iOS, macOS, WINDOWS (WinRT synthesizer) and Linux
  /// (speech-dispatcher, when the distro has it). No gate — an engine that
  /// isn't there simply fails into silence, never into a crash.
  static Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.5); // unhurried, low cognitive load
    _configured = true;
  }

  /// Read any kept words aloud — the voice side of "showing the text to
  /// the person". One voice at a time: speaking replaces what was playing.
  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    try {
      await _ensureConfigured();
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Silence is fine — reading aloud is a courtesy, never a blocker.
    }
  }

  /// Speak [subject] and only return once the engine finished talking
  /// (so callers can start the mic right after without recording the prompt).
  static Future<void> speakSubject(String subject) => speak(subject);

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
