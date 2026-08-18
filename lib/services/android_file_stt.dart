import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// THE ANDROID FILE EAR (owner, 2026-08-18: "רציתי שמהתחלה יהיה גם הקלטה
/// וגם יצירת טקסט מהדיבור... לגרום לגוגל להוציא מילים מההקלטה גם מגניב").
///
/// For a year the phone had no ear for a finished file — the recorder and
/// the live engine cannot share one microphone (field truth, 2026-07-26),
/// so words meant SAYING IT AGAIN into the popup. Android 13 quietly ended
/// that: RecognizerIntent.EXTRA_AUDIO_SOURCE feeds the popup's own engine
/// from a file descriptor instead of the mic. One speaking — the voice is
/// kept AND the same audio becomes words, curses included (masking off).
///
/// Phones differ on which recognizer honors the extra, so the first use
/// PROBES: a bundled recorded sentence ("שלום, מה שלומך היום?", spoken by
/// the Mac's own Hebrew voice) is played to each recognizer variant —
/// on-device, Google's service by name, the system default — and the first
/// one that hears it is remembered in a sidecar file (device truth, never
/// synced). A phone where no door works keeps the popup flow, unchanged.
class AndroidFileStt {
  AndroidFileStt._();

  static const _channel = MethodChannel('bns/file_stt');
  static const _probeAsset = 'assets/audio/ear_probe_he.wav';

  static bool get isSupported => Platform.isAndroid;

  /// This run's verdict. null = unknown yet; -1 = nothing works (memory
  /// only — a phone that was merely offline gets a fresh probe next run);
  /// 0..2 = the variant the sidecar remembers.
  static int? _variant;
  static bool _probedThisRun = false;

  static Future<String> transcribeFile(String path,
      {String locale = 'he-IL'}) async {
    if (!isSupported || path.isEmpty) return '';
    try {
      if (await _channel.invokeMethod<bool>('isSupported') != true) return '';
      final v = await _resolveVariant();
      if (v < 0) return '';
      final words = await _channel.invokeMethod<String>('transcribeFile', {
        'path': path,
        'locale': locale,
        'variant': v,
        'timeoutMs': 90000,
      });
      return (words ?? '').trim();
    } on PlatformException catch (e) {
      debugPrint('BNS file ear failed: ${e.code}');
      // A variant that once answered the probe and breaks now (speech
      // service updated, pack removed): forget it, the next take probes
      // fresh instead of failing forever.
      if (e.code != 'busy') await _forget();
      return '';
    } catch (_) {
      return '';
    }
  }

  static Future<int> _resolveVariant() async {
    final known = _variant;
    if (known != null) return known;
    final side = await _sidecar();
    try {
      if (await side.exists()) {
        final saved = int.tryParse((await side.readAsString()).trim());
        if (saved != null && saved >= 0 && saved <= 2) {
          _variant = saved;
          return saved;
        }
      }
    } catch (_) {}
    // One probe per run: a broken/offline phone costs a few quiet seconds
    // once, not on every take.
    if (_probedThisRun) return _variant ?? -1;
    _probedThisRun = true;
    final found = await _probe();
    _variant = found;
    if (found >= 0) {
      try {
        await side.writeAsString('$found');
      } catch (_) {}
    }
    debugPrint('BNS file ear probe: variant=$found');
    return found;
  }

  /// Speak the bundled sentence at every door; the first door that hears
  /// it is this phone's ear. The asset is Hebrew — the flagship person
  /// speaks Hebrew, and a door that honors the file extra honors it in
  /// every language its engine carries.
  static Future<int> _probe() async {
    try {
      final support = await getApplicationSupportDirectory();
      final probe = File(p.join(support.path, 'ear_probe.wav'));
      if (!await probe.exists()) {
        final bytes = await rootBundle.load(_probeAsset);
        await probe.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      }
      for (final v in const [0, 1, 2]) {
        try {
          final heard = await _channel.invokeMethod<String>('transcribeFile', {
            'path': probe.path,
            'locale': 'he-IL',
            'variant': v,
            // A short leash: three dead doors must cost seconds, not
            // minutes of «כותבים את המילים…» over a disabled mic.
            'timeoutMs': 15000,
          });
          if (probeMatches(heard ?? '')) return v;
        } on PlatformException {
          continue; // this door is closed — knock on the next
        }
      }
    } catch (_) {}
    return -1;
  }

  /// Loose match: the engine may punctuate or reshape, but the sentence's
  /// solid words must be there. Final letters are folded so שלום is found
  /// inside שלומך too — and an empty or ambient answer never passes.
  @visibleForTesting
  static bool probeMatches(String heard) {
    final flat = heard
        .replaceAll('ם', 'מ')
        .replaceAll('ן', 'נ')
        .replaceAll('ץ', 'צ')
        .replaceAll('ף', 'פ')
        .replaceAll('ך', 'כ');
    return flat.contains('שלומ') &&
        (flat.contains('היומ') || flat.contains('מה'));
  }

  static Future<File> _sidecar() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'file_ear.txt'));
  }

  static Future<void> _forget() async {
    _variant = null;
    try {
      final side = await _sidecar();
      if (await side.exists()) await side.delete();
    } catch (_) {}
  }
}
