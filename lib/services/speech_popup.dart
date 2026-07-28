import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// THE WAZE DOOR (owner's phone, 2026-07-26: "it's so odd that it doesn't
/// work — in Waze it's flawless").
///
/// Field evidence from the S23: the EMBEDDED recognizer refuses Hebrew
/// (error_language_not_supported for he_IL and iw_IL, then
/// error_server_disconnected), while Google's speech POPUP — the one Waze
/// and the keyboard mic use — transcribes Hebrew perfectly on the same
/// phone. That popup is a plain system Intent any app may open.
///
/// So Hebrew dictation goes through the door that works: the person taps
/// the mic, the familiar Google listening screen appears, they speak, and
/// the words come back into the field. One utterance per tap — which suits
/// people who need one clear step at a time better than an endless stream.
class SpeechPopup {
  SpeechPopup._();

  static const _channel = MethodChannel('bns/speech_popup');

  /// Only Android has this door (iOS/desktop use the embedded engine).
  static bool get isSupported => Platform.isAndroid;

  /// Opens the system listening screen and returns what was understood.
  /// Empty string = cancelled or nothing heard. Null = the door itself is
  /// unavailable, so callers can fall back to the embedded engine.
  static Future<String?> recognize({String? locale, String? prompt}) async {
    if (!isSupported) return null;
    try {
      final words = await _channel.invokeMethod<String>('recognize', {
        'locale': locale,
        'prompt': prompt,
      });
      return words ?? '';
    } on PlatformException catch (e) {
      debugPrint('BNS speech popup unavailable: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('BNS speech popup failed: $e');
      return null;
    }
  }
}

// WINDOWS VOICE TYPING (Win+H) was tried here and REMOVED (owner's test,
// 2026-07-27: "this is invalid for English (Israel) for no reason, so no
// English transcript and no Hebrew"). Summoning the OS overlay refused his
// own display language, and an overlay cannot be trusted to type into the
// right field anyway. Windows now hears through whisper.cpp, which reads
// the recording afterwards — see WhisperService. Do not resurrect this.
