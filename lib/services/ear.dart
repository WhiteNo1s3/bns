import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/android_file_stt.dart';
import 'package:bns/services/apple_file_stt.dart';
import 'package:bns/services/vosk_service.dart';
import 'package:bns/services/whisper_ear.dart';
import 'package:bns/services/whisper_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// ONE EAR FOR THE WHOLE APP.
///
/// Words always come from a KEPT RECORDING, never from a live session that
/// dies when a finger lands on the screen (owner, 2026-08-19: "sst less
/// fragile than android simple one that cancel itself when you press any
/// point of the screen"). The person presses once, speaks, presses again —
/// the voice is safe the moment recording stops, and the words are read off
/// that same take afterwards. Nothing to hold still, nothing to hurry.
///
/// The rungs, in the order they are tried:
///   1. [WhisperEar] — whisper.cpp inside the app. Once its model is
///      downloaded this is the ear on EVERY platform: offline, identical
///      words everywhere, and it belongs to nobody but this phone. A person
///      who chose to install it chose it first.
///   2. The platform's own file ear — Google on Android 13+, Apple's
///      on-device recognizer on iOS/macOS. Free, fast, and very good at
///      Hebrew, but it exists only where it exists.
///   3. The downloaded whisper-cli (Windows) and Vosk (English) doors that
///      served before the ear moved inside the app.
///
/// Every rung answers '' rather than throwing: a take nobody could read
/// still keeps its voice, and typing always works.
class Ear {
  Ear._();

  /// True when SOME ear could answer on this device — for doors that want
  /// to say "words will follow" before the person speaks.
  static Future<bool> get hasAnyEar async {
    if (await WhisperEar.isInstalled()) return true;
    if (AndroidFileStt.isSupported || AppleFileStt.isSupported) return true;
    final support = await getApplicationSupportDirectory();
    return WhisperService.isInstalled(p.join(support.path, 'whisper')) ||
        VoskService.isInstalled(p.join(support.path, 'vosk'));
  }

  /// The language this person speaks, as the settings hold it ('he-IL').
  static Future<String> spokenLocale() async {
    final settings = await IsarService.getSettings();
    final chosen = settings.sttLocale.trim();
    if (chosen.isEmpty) return L.isHebrew ? 'he-IL' : 'en-US';
    return chosen.replaceAll('_', '-');
  }

  /// 'he-IL' -> 'he'. Whisper wants the bare language.
  static String bareLang(String locale) {
    final lang = locale.replaceAll('_', '-').split('-').first.toLowerCase();
    // Hebrew wore `iw` before it wore `he`, and old settings still say so.
    return lang == 'iw' ? 'he' : (lang.isEmpty ? 'he' : lang);
  }

  /// ONE READING AT A TIME (owner, 2026-08-19: "it sometimes won't press
  /// the button and freezes... because I did right after you the
  /// recordings"). Speaking again while the last take is still being read
  /// is NORMAL — people talk in bursts — but the engines underneath are
  /// not: two whisper reads at once fight over the same parked model and
  /// hundreds of megabytes of memory, and the borrowed engines allow one
  /// session each. So the takes QUEUE here instead of colliding, in the
  /// order they were spoken, and the microphone stays free the whole time.
  static Future<void> _queue = Future<void>.value();

  @visibleForTesting
  static Future<T> inTurn<T>(Future<T> Function() job) {
    final mine = _queue.then((_) => job());
    // The chain must survive a failed read, or one bad take would jam
    // every take after it, forever.
    _queue = mine.then((_) {}, onError: (_) {});
    return mine;
  }

  /// Read the words out of [path]. Returns '' when no ear could answer —
  /// and '' is never an error: the voice is already kept.
  ///
  /// A person who turned voice typing off in settings gets silence from
  /// every rung: "no engine listens to me" is a promise, not a preference.
  static Future<String> hear(String path) => inTurn(() => _hearNow(path));

  /// Let the offline ear give its memory back — the model stays parked in
  /// native memory between takes so the next one is quick, and a room the
  /// person has left has no reason to hold it.
  static Future<void> rest() => WhisperEar.rest();

  static Future<String> _hearNow(String path) async {
    if (path.isEmpty) return '';
    final settings = await IsarService.getSettings();
    if (!settings.sttEnabled) return '';
    final locale = await spokenLocale();

    try {
      if (await WhisperEar.isInstalled()) {
        final heard = await WhisperEar.transcribeFile(
          path,
          lang: bareLang(locale),
        );
        if (heard.isNotEmpty) return heard;
      }

      if (AndroidFileStt.isSupported) {
        final heard = await AndroidFileStt.transcribeFile(path, locale: locale);
        if (heard.isNotEmpty) return heard;
      } else if (AppleFileStt.isSupported) {
        final heard = await AppleFileStt.transcribeFile(path, locale: locale);
        if (heard.isNotEmpty) return heard;
      }

      // The desktop doors that came before the ear moved inside the app.
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final support = await getApplicationSupportDirectory();
        final whisperDir = p.join(support.path, 'whisper');
        if (WhisperService.isInstalled(whisperDir)) {
          final heard = await WhisperService.transcribeWav(
            whisperDir,
            path,
            language: bareLang(locale),
          );
          if (heard.trim().isNotEmpty) return heard.trim();
        }
        final voskDir = p.join(support.path, 'vosk');
        if (VoskService.isInstalled(voskDir)) {
          final heard = await VoskService.transcribeWav(voskDir, path);
          if (heard.trim().isNotEmpty) return heard.trim();
        }
      }
    } catch (_) {}
    return '';
  }
}
