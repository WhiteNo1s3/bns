import 'dart:async';

import 'package:bns/core/i18n/l.dart';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// What a dictation session is currently doing (for gentle UI hints).
enum SttState {
  /// Engine not started, or stopped by the user.
  idle,

  /// Mic is open and words are landing.
  listening,

  /// Between engine sessions — the auto-restart gap. Still "on" to the user.
  restarting,

  /// The device has no usable speech engine (or permission was denied).
  /// Typing and plain voice recording still work — never a dead end.
  unavailable,
}

/// Speech-to-text with the DEVICE engine — free, on-device where the platform
/// supports it, no cloud accounts, no subscriptions (same rules as
/// [TtsService]).
///
/// "STT all the time": the platform engines stop on their own after a pause
/// or a timeout, so this service wraps them in a session that auto-restarts
/// until the user says stop. Text accumulates across those engine restarts —
/// the caller only ever sees one growing transcript.
///
/// One dictation session at a time (one mic, one person).
class SttService {
  SttService._();

  static final SpeechToText _speech = SpeechToText();
  static bool _initialized = false;
  static bool _available = false;

  // --- Session state ---
  static bool _wantListening = false;
  static String _finalText = ''; // finished sentences, across engine restarts
  static String _partialText = ''; // words still forming in this engine run
  static void Function(String text)? _onText;
  static void Function(SttState state)? _onState;
  static String? _localeId;
  static Timer? _restartTimer;
  static int _consecutiveErrors = 0;

  /// True after a successful [init]. When false, dictation quietly does
  /// nothing — recording and typing are always the safety net.
  static bool get isAvailable => _available;

  /// True while a dictation session is on (including auto-restart gaps).
  static bool get isDictating => _wantListening;

  /// Initialize the device engine once. Safe to call repeatedly.
  /// A FAILED init is retried on the next call — engines appear (permission
  /// granted, service installed) without the app restarting.
  static Future<bool> init() async {
    if (_initialized && _available) return _available;
    try {
      _available = await _speech.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
        debugLogging: kDebugMode,
        // Some phones point their "default" recognizer at a service that
        // cannot actually recognize (owner's S23: the TTS package). Intent
        // lookup finds one that works instead of trusting the default.
        options: [SpeechToText.androidIntentLookup],
      );
      debugPrint('BNS STT: initialize -> $_available');
    } catch (e) {
      debugPrint('BNS STT: initialize threw: $e');
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  /// Locales the device engine can transcribe (shown in settings).
  static Future<List<LocaleName>> locales() async {
    if (!await init()) return const [];
    try {
      return await _speech.locales();
    } catch (_) {
      return const [];
    }
  }

  /// Begin a continuous dictation session.
  ///
  /// [onText] receives the FULL accumulated transcript (finished + forming)
  /// every time it changes. [onState] is optional UI feedback.
  /// [localeId] empty/null = device default language.
  ///
  /// Returns false when the engine is unavailable or the mic is busy —
  /// callers just skip the transcript, never block the person.
  static Future<bool> start({
    required void Function(String text) onText,
    void Function(SttState state)? onState,
    String? localeId,
  }) async {
    if (!await init()) {
      onState?.call(SttState.unavailable);
      return false;
    }
    // A new session replaces any previous one (one mic, one person).
    await stop();

    _onText = onText;
    _onState = onState;
    // No explicit choice? Follow the app language — Hebrew app, Hebrew ears.
    _localeId = (localeId == null || localeId.trim().isEmpty)
        ? (L.isHebrew ? 'he_IL' : null)
        : localeId;
    _finalText = '';
    _partialText = '';
    _consecutiveErrors = 0;
    _wantListening = true;

    final ok = await _listenOnce();
    if (!ok) {
      // Mic busy (e.g. some devices refuse STT while a recorder runs) or
      // engine hiccup. Report unavailable for THIS session; not fatal.
      _wantListening = false;
      _onState?.call(SttState.unavailable);
      return false;
    }
    _emitState(SttState.listening);
    return true;
  }

  /// End the session and return everything understood so far.
  static Future<String> stop() async {
    _wantListening = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (_) {}
    final text = currentText;
    _onState?.call(SttState.idle);
    _onText = null;
    _onState = null;
    return text;
  }

  /// The transcript as it stands right now (finished + forming words).
  static String get currentText {
    final f = _finalText.trim();
    final p = _partialText.trim();
    if (f.isEmpty) return p;
    if (p.isEmpty) return f;
    return '$f $p';
  }

  // --- Engine plumbing ---

  static Future<bool> _listenOnce() async {
    try {
      await _speech.listen(
        onResult: _handleResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          autoPunctuation: true,
          localeId: _localeId,
          // Long windows; the auto-restart loop covers engines that stop early.
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 10),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('BNS STT: listen threw: $e');
      return false;
    }
  }

  static void _handleResult(SpeechRecognitionResult result) {
    if (!_wantListening) return;
    _consecutiveErrors = 0;
    if (result.finalResult) {
      // Engine run finished a sentence — bank it, clear the forming buffer.
      final words = result.recognizedWords.trim();
      if (words.isNotEmpty) {
        _finalText = _finalText.isEmpty ? words : '$_finalText $words';
      }
      _partialText = '';
    } else {
      _partialText = result.recognizedWords;
    }
    _onText?.call(currentText);
  }

  static void _handleStatus(String status) {
    // 'done'/'notListening' mid-session = the engine gave up on its own
    // (pause timeout, platform limit). The person didn't stop — restart.
    if (_wantListening && (status == 'done' || status == 'notListening')) {
      _scheduleRestart();
    }
  }

  static void _handleError(SpeechRecognitionError error) {
    debugPrint('BNS STT: error ${error.errorMsg} permanent=${error.permanent}');
    if (!_wantListening) return;
    _consecutiveErrors++;
    // A run of permanent errors means it's truly not working (no permission,
    // no engine, mic taken) — stop pretending, tell the UI once.
    if (_consecutiveErrors >= 4 && error.permanent) {
      _wantListening = false;
      _restartTimer?.cancel();
      _onState?.call(SttState.unavailable);
      return;
    }
    // 'no match' / timeouts are normal in quiet rooms — just go again.
    _scheduleRestart();
  }

  static void _scheduleRestart() {
    if (!_wantListening || (_restartTimer?.isActive ?? false)) return;
    _emitState(SttState.restarting);
    // Small backoff so repeated errors don't spin the mic.
    final delay = Duration(milliseconds: 250 + 500 * _consecutiveErrors);
    _restartTimer = Timer(delay, () async {
      if (!_wantListening) return;
      if (_speech.isListening) return; // engine recovered on its own
      final ok = await _listenOnce();
      if (ok) {
        _emitState(SttState.listening);
      } else {
        _scheduleRestart(); // try again, backoff grows with error count
        _consecutiveErrors++;
      }
    });
  }

  static void _emitState(SttState s) => _onState?.call(s);
}
