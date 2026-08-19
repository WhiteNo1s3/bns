import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// THE EAR THAT BELONGS TO THIS PHONE (owner, 2026-08-19: "we find a way to
/// sst less fragile than android simple one that cancel itself when you
/// press any point of the screen... record package + any Whisper package").
///
/// Every other ear in this app is borrowed. Google's file ear works only on
/// Android 13+, only when a recognizer on THIS phone honors the file extra,
/// and only while Google's service is in the mood; Apple's ear is Apple's;
/// the Windows ear is a downloaded exe. whisper.cpp compiled INTO the app is
/// none of those: same code on Android, iOS, macOS, Windows and Linux, no
/// account, no network after the model lands, nothing that cancels itself
/// because a finger touched the screen.
///
/// The model is a single file the person chooses to download once.
/// `small` is the first rung where Hebrew is genuinely usable — `base`
/// mangles it (field truth, 2026-07-27, unchanged since).
class WhisperEar {
  WhisperEar._();

  /// Hebrew needs `small`. `base` mangles it (field truth, 2026-07-27).
  static const model = WhisperModel.small;

  /// QUANTIZED, and deliberately (2026-08-19). The plain `small` weights are
  /// 488 MB — a rude thing to ask of a phone that also holds the person's
  /// life. whisper.cpp's own q5_1 build of the SAME model is 190 MB and
  /// loads through the identical code path; the words lose almost nothing.
  /// It lands under the name the plugin looks for, so nothing else has to
  /// know it is quantized.
  static final Uri _modelUri = Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
      'ggml-small-q5_1.bin');

  /// Roughly what the download costs, for the door that offers it.
  static const modelBytesApprox = 190 * 1024 * 1024;

  static final _controller = WhisperController();

  /// whisper.cpp has a native build for every platform BNS ships to.
  static bool get isSupportedPlatform =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  static Future<String> modelPath() => _controller.getPath(model);

  /// True when the model file is on this device — the only thing that
  /// separates "installed" from "not".
  static Future<bool> isInstalled() async {
    if (!isSupportedPlatform) return false;
    try {
      final f = File(await modelPath());
      if (!f.existsSync()) return false;
      // A half-finished download is not an ear. Anything under 100 MB
      // cannot be this model, so treat it as absent.
      return await f.length() > 100 * 1024 * 1024;
    } catch (_) {
      return false;
    }
  }

  /// Read the words out of a recording. Returns '' when nothing was heard
  /// (silence, or the model is not installed) — never throws at the caller.
  ///
  /// The plugin carries ffmpeg on Android/iOS/macOS, so the phone's own
  /// m4a takes are read as they are. Windows and Linux need 16 kHz mono
  /// WAV, which is exactly what BNS records on a desktop.
  static Future<String> transcribeFile(
    String path, {
    String lang = 'he',
  }) async {
    if (path.isEmpty || !await isInstalled()) return '';
    try {
      final res = await _controller.transcribe(
        model: model,
        audioPath: path,
        lang: lang,
        // Nothing but words: no [MUSIC], no (silence), no timestamps.
        suppressNonSpeechTokens: true,
        // NO CARRIED CONTEXT (lived on the S23, 2026-08-19). Fed a quiet
        // take with a faint voice in it, whisper feeds its own last guess
        // back into the next window and loops — a field dictation came out
        // as «קצת רגלת כתובילים תודה רגלת כתובילים». Each window judged on
        // its own audio alone stops the loop from building.
        noContext: true,
        // The next take skips the multi-second model load. A voice note is
        // rarely alone — people speak twice.
        keepModelLoaded: true,
      );
      return (res?.transcription.text ?? '').trim();
    } catch (e) {
      debugPrint('BNS whisper ear failed: $e');
      return '';
    } finally {
      // THE CRUMB IT LEAVES (lived on the S23, 2026-08-19). To read an m4a
      // the plugin's ffmpeg writes a 16 kHz WAV called '<take>.m4a.wav' —
      // right next to the take, five times its size, and it never cleans up
      // after itself. That folder is the person's kept VOICE: it is packed
      // into .bns files and carried over sync. The crumb goes.
      try {
        final crumb = File('$path.wav');
        if (crumb.existsSync()) {
          await crumb.delete();
        }
      } catch (_) {}
    }
  }

  /// Give the parked model its memory back (screen closed, app paused).
  static Future<void> rest() async {
    try {
      await _controller.releaseModel();
    } catch (_) {}
  }

  /// Fetch the model once. [onProgress] is 0..1 for the settings door;
  /// the file lands under a temporary name so a cancelled or crashed
  /// download can never be mistaken for an installed ear.
  static Future<void> install({void Function(double p)? onProgress}) async {
    final dest = File(await modelPath());
    final partial = File('${dest.path}.part');
    final client = HttpClient();
    try {
      var target = _modelUri;
      HttpClientResponse? res;
      // Hugging Face answers with a redirect to its CDN.
      for (var hop = 0; hop < 5 && res == null; hop++) {
        final req = await client.getUrl(target);
        req.followRedirects = false;
        final r = await req.close();
        if (r.statusCode >= 300 && r.statusCode < 400) {
          final loc = r.headers.value(HttpHeaders.locationHeader);
          await r.drain<void>();
          if (loc == null) {
            throw const HttpException('redirect without location');
          }
          target = Uri.parse(loc);
          continue;
        }
        if (r.statusCode != 200) {
          throw HttpException('HTTP ${r.statusCode} for $target');
        }
        res = r;
      }
      if (res == null) throw const HttpException('too many redirects');

      final total = res.contentLength > 0
          ? res.contentLength
          : modelBytesApprox;
      final sink = partial.openWrite();
      var got = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          onProgress?.call((got / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
      if (await partial.length() < 100 * 1024 * 1024) {
        throw const HttpException('model download came back too small');
      }
      if (dest.existsSync()) {
        await dest.delete();
      }
      await partial.rename(dest.path);
      onProgress?.call(1.0);
    } finally {
      client.close();
      if (partial.existsSync()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  /// THE ONE-TIME OFFER (owner, 2026-08-19: "we should push into this as
  /// the new standard"). A standard nobody is told about is a setting. The
  /// capture room offers the ear once; a person who says «לא עכשיו» is not
  /// asked again, and the answer is DEVICE TRUTH — a sidecar file, never a
  /// synced setting, because it is about this phone's storage and not about
  /// how the person wants to live.
  static Future<bool> offerDeclined() async {
    try {
      return (await _declineMark()).existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<void> declineOffer() async {
    try {
      await (await _declineMark()).writeAsString('not now');
    } catch (_) {}
  }

  static Future<File> _declineMark() async {
    final dir = await WhisperController.getModelDir();
    return File('$dir/ear_offer_declined.txt');
  }

  /// Give the storage back. The borrowed ears keep working.
  static Future<void> remove() async {
    try {
      await rest();
      final f = File(await modelPath());
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
