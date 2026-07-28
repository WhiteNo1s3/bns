import 'dart:async';
import 'dart:io' show Platform;

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

  /// The engine's reason for the most recent PERMANENT error (e.g.
  /// 'error_language_not_supported'), so the UI can say WHY dictation
  /// stopped instead of failing silently. Cleared when a session starts.
  static String? lastErrorMsg;

  /// True after a successful [init]. When false, dictation quietly does
  /// nothing — recording and typing are always the safety net.
  static bool get isAvailable => _available;

  /// True while a dictation session is on (including auto-restart gaps).
  static bool get isDictating => _wantListening;

  /// Initialize the device engine once. Safe to call repeatedly.
  /// A FAILED init is retried on the next call — engines appear (permission
  /// granted, service installed) without the app restarting.
  /// Live dictation exists on Android/iOS/macOS only — the speech_to_text
  /// plugin has NO desktop-Windows/Linux implementation, and calling it
  /// there throws a MissingPluginException that took the capture screen
  /// down mid-save (owner's PC, 2026-07-27). On those desktops words come
  /// from the recording instead, read by whisper afterwards.
  static bool get isSupportedPlatform =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static Future<bool> init() async {
    if (!isSupportedPlatform) {
      _initialized = true;
      _available = false;
      return false;
    }
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
    lastErrorMsg = null;
    // No explicit choice? Follow the app language — Hebrew app, Hebrew ears.
    final want = (localeId == null || localeId.trim().isEmpty)
        ? (L.isHebrew ? 'he_IL' : null)
        : localeId.trim();
    // Build the ladder ONCE per session; the error handler steps down it
    // when the engine rejects a language, so Hebrew gets its honest try
    // before anything falls back.
    _localeCandidates = await _buildLocaleCandidates(want);
    _candIdx = 0;
    _localeId = _activeLocaleId;
    debugPrint('BNS STT: ladder for ${want ?? '(device default)'}: '
        '${_localeCandidates.map((c) => c.isEmpty ? '(default)' : c).join(' -> ')}');
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

  /// The ladder of locale ids to TRY, in order. '' means device default.
  /// FIELD TRUTH (owner's phone, 2026-07-26, round 2): the engine's
  /// advertised list LIES — it often only names installed offline packs,
  /// while online recognition happily does more languages. Surrendering to
  /// the list turned a Hebrew app into an English mic. So: engine match
  /// first when one exists, then OPTIMISM — the wanted id anyway, then its
  /// sibling spelling (Hebrew answers to both 'he' and 'iw'), and only
  /// then the device default. A language the engine truly rejects answers
  /// with error_language_not_supported and the ladder steps down.
  static List<String> _localeCandidates = const [''];
  static int _candIdx = 0;

  static String? get _activeLocaleId {
    final id = _localeCandidates[_candIdx];
    return id.isEmpty ? null : id;
  }

  /// 'he_IL' <-> 'iw_IL' — Hebrew's two ISO spellings. Null for others.
  static String? _siblingSpelling(String id) {
    final parts = id.replaceAll('-', '_').split('_');
    final lang = parts.first.toLowerCase();
    if (lang != 'he' && lang != 'iw') return null;
    parts[0] = lang == 'he' ? 'iw' : 'he';
    return parts.join('_');
  }

  static Future<List<String>> _buildLocaleCandidates(String? want) async {
    if (want == null) return const [''];
    List<LocaleName> engineLocales;
    try {
      engineLocales = await _speech.locales();
    } catch (_) {
      engineLocales = const [];
    }
    String norm(String s) => s.toLowerCase().replaceAll('-', '_');
    final wantNorm = norm(want);
    final out = <String>[];
    // The engine's own id for this language, when it admits to one.
    for (final l in engineLocales) {
      if (norm(l.localeId) == wantNorm) {
        out.add(l.localeId);
        break;
      }
    }
    if (out.isEmpty) {
      final lang = wantNorm.split('_').first;
      final prefixes =
          (lang == 'he' || lang == 'iw') ? const ['he', 'iw'] : [lang];
      for (final l in engineLocales) {
        if (prefixes.contains(norm(l.localeId).split('_').first)) {
          out.add(l.localeId);
          break;
        }
      }
    }
    // Optimism: ask for what we want even if unadvertised.
    if (!out.map(norm).contains(wantNorm)) out.add(want);
    final sibling = _siblingSpelling(want);
    if (sibling != null && !out.map(norm).contains(norm(sibling))) {
      out.add(sibling);
    }
    out.add(''); // device default — the mic must never die over language
    return out;
  }

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
      // WORDS NEVER DELETE THEMSELVES (owner's phone, 2026-07-26): when the
      // engine's final result comes back EMPTIER than the partial the
      // person already saw on screen, the partial is the truth — bank it.
      var words = result.recognizedWords.trim();
      if (words.length < _partialText.trim().length) {
        words = _partialText.trim();
      }
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
    if (error.permanent) lastErrorMsg = error.errorMsg;
    if (!_wantListening) return;
    // Language rejected? Step DOWN the ladder and go again — this is how
    // he_IL -> iw_IL -> device default happens without the person noticing
    // anything but a working mic.
    if (error.errorMsg.contains('language') &&
        _candIdx + 1 < _localeCandidates.length) {
      _candIdx++;
      _localeId = _activeLocaleId;
      _consecutiveErrors = 0;
      debugPrint('BNS STT: language rejected, stepping to '
          '${_localeId ?? '(device default)'}');
      _scheduleRestart();
      return;
    }
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
    // The engine gave up mid-utterance: the forming words on screen must
    // SURVIVE the restart, not vanish — bank them before the new run.
    final forming = _partialText.trim();
    if (forming.isNotEmpty) {
      _finalText = _finalText.isEmpty ? forming : '$_finalText $forming';
      _partialText = '';
      _onText?.call(currentText);
    }
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
