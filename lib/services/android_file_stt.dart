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
/// that: RecognizerIntent.EXTRA_AUDIO_SOURCE feeds a recognizer from a
/// file descriptor instead of the mic — as a SEGMENTED session, the
/// documented pairing (S23 field truth, 2026-08-19: without it Google's
/// service closed the session in half a second, empty).
///
/// Phones differ on which recognizer honors the extra, so the first use
/// PROBES: the Kotlin side lists this phone's doors (on-device, Google's
/// services by name, the system default — never a third party), and a
/// bundled recorded sentence ("שלום, מה שלומך היום?") knocks on each.
/// The first door that hears it is remembered in a sidecar file (device
/// truth, never synced). A phone where no door works keeps the popup
/// flow unchanged — and asks the on-device engine to DOWNLOAD the Hebrew
/// pack (API 33), so a later run may find a fully offline door open.
class AndroidFileStt {
  AndroidFileStt._();

  static const _channel = MethodChannel('bns/file_stt');
  static const _probeAsset = 'assets/audio/ear_probe_he.wav';

  static bool get isSupported => Platform.isAndroid;

  /// This run's verdict. null = unknown yet; '' = nothing works (memory
  /// only — a phone that was merely offline gets a fresh probe next run);
  /// otherwise the door the sidecar remembers.
  static String? _door;
  static bool _probedThisRun = false;
  static bool _askedForPack = false;

  static Future<String> transcribeFile(String path,
      {String locale = 'he-IL'}) async {
    if (!isSupported || path.isEmpty) return '';
    try {
      if (await _channel.invokeMethod<bool>('isSupported') != true) return '';
      final door = await _resolveDoor();
      if (door.isEmpty) return '';
      // Hebrew wore `iw` before it wore `he`, and old settings still say
      // so. The popup activity forgives the legacy code; the recognition
      // SERVICE answers it with LANGUAGE_NOT_SUPPORTED (S23 field truth,
      // 2026-08-19) — so the ear always speaks the modern name.
      final spoken = locale.toLowerCase().startsWith('iw')
          ? 'he${locale.substring(2)}'
          : locale;
      final words = await _channel.invokeMethod<String>('transcribeFile', {
        'path': path,
        'locale': spoken,
        'door': door,
        'timeoutMs': 90000,
      });
      return (words ?? '').trim();
    } on PlatformException catch (e) {
      debugPrint('BNS file ear failed: ${e.code}');
      // Forget the door only when the DOOR is broken (missing service,
      // language gone, refused start). Network moods — server drops,
      // timeouts, busy — pass; the probed door itself stays trusted.
      const doorBroken = {'ear_9', 'ear_12', 'ear_13', 'ear_start', 'bad_door'};
      if (e.code.startsWith('no_') || doorBroken.contains(e.code)) {
        await _forget();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> _resolveDoor() async {
    final known = _door;
    if (known != null) return known;
    final side = await _sidecar();
    try {
      if (await side.exists()) {
        final saved = (await side.readAsString()).trim();
        // Old sidecars held a variant number; a door is a word or a
        // component path. Anything else re-probes.
        if (saved.isNotEmpty && !RegExp(r'^-?\d+$').hasMatch(saved)) {
          _door = saved;
          return saved;
        }
      }
    } catch (_) {}
    // One probe per run: a broken/offline phone costs a few quiet seconds
    // once, not on every take.
    if (_probedThisRun) return _door ?? '';
    _probedThisRun = true;
    final found = await _probe();
    _door = found;
    if (found.isNotEmpty) {
      try {
        await side.writeAsString(found);
      } catch (_) {}
    } else if (!_askedForPack) {
      // No door heard Hebrew — ask the on-device engine to fetch the
      // pack. If it lands, a future run's probe opens the offline door.
      _askedForPack = true;
      try {
        await _channel.invokeMethod('suggestDownload', {'locale': 'he-IL'});
      } catch (_) {}
    }
    debugPrint('BNS file ear probe: door=${found.isEmpty ? 'none' : found}');
    return found;
  }

  /// Speak the bundled sentence at every door this phone offers; the
  /// first door that hears it is this phone's ear. The asset is Hebrew —
  /// the flagship person speaks Hebrew, and a door that honors the file
  /// extra honors it in every language its engine carries.
  static Future<String> _probe() async {
    try {
      final support = await getApplicationSupportDirectory();
      final probe = File(p.join(support.path, 'ear_probe.wav'));
      if (!await probe.exists()) {
        final bytes = await rootBundle.load(_probeAsset);
        await probe.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      }
      final doors =
          await _channel.invokeMethod<List<dynamic>>('ears') ?? const [];
      for (final d in doors.cast<String>()) {
        try {
          final heard = await _channel.invokeMethod<String>('transcribeFile', {
            'path': probe.path,
            'locale': 'he-IL',
            'door': d,
            // A short leash: dead doors must cost seconds, not minutes
            // of «כותבים את המילים…» over a disabled mic.
            'timeoutMs': 15000,
          });
          if (probeMatches(heard ?? '')) return d;
        } on PlatformException {
          continue; // this door is closed — knock on the next
        }
      }
    } catch (_) {}
    return '';
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
    _door = null;
    try {
      final side = await _sidecar();
      if (await side.exists()) await side.delete();
    } catch (_) {}
  }
}
