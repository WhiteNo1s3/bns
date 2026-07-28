import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

/// THE EAR THAT HEARS HEBREW (owner, 2026-07-27: "we need to dive into
/// hebrew as english worked with the older solution").
///
/// Everything else on this desktop is deaf to Hebrew, and each was checked,
/// not assumed:
///   * Vosk — the English ear that already works here — has no Hebrew model
///     at all (20+ languages, Hebrew is not among them).
///   * Windows' app-callable engines (legacy System.Speech, WinRT
///     SpeechRecognizer) report en-GB/en-US only on this machine.
///   * Windows Voice typing (Win+H) does know Hebrew, but it is an OS
///     overlay no app may call — and it refuses the owner's own display
///     language, English (Israel).
///
/// whisper.cpp is the honest answer: Apache-2.0, fully offline, and
/// genuinely multilingual — Hebrew included. The project ships a small
/// Windows build (8 MB) whose whisper-cli reads a WAV and prints the words;
/// the model is a single file beside it. No cloud, no accounts, no ads —
/// the same law as the rest of BNS.
///
/// On disk, inside the app's own folder:
///   <baseDir>/whisper-cli.exe (+ its DLLs)
///   <baseDir>/model.bin
class WhisperService {
  WhisperService._();

  /// The project's official Windows build (CPU, no BLAS — small and
  /// dependency-free; a laptop transcribes a voice note in seconds).
  static const engineUrl =
      'https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-bin-x64.zip';

  /// `small` is the first rung where Hebrew is genuinely usable; `base`
  /// mangles it. 465 MB once, then never again.
  static const modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin';

  static String exePath(String baseDir) => '$baseDir${sep}whisper-cli.exe';
  static String modelPath(String baseDir) => '$baseDir${sep}model.bin';
  static String get sep => Platform.pathSeparator;

  static bool isInstalled(String baseDir) =>
      File(exePath(baseDir)).existsSync() &&
      File(modelPath(baseDir)).existsSync();

  /// Fetch engine + model into [baseDir]. ~473 MB, one time.
  /// [onStatus] narrates for the settings screen.
  static Future<void> install(String baseDir,
      {void Function(String status)? onStatus}) async {
    final dir = Directory(baseDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    onStatus?.call('Fetching the engine (about 8 MB)…');
    final engineZip = await _download(engineUrl);
    onStatus?.call('Unpacking the engine…');
    // The zip nests everything under Release/ — flatten it, the exe and its
    // DLLs must sit side by side.
    for (final f in ZipDecoder().decodeBytes(engineZip).files) {
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      final lower = name.toLowerCase();
      if (!lower.endsWith('.dll') && !lower.endsWith('.exe')) continue;
      File('$baseDir$sep$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.content as List<int>);
    }

    onStatus?.call('Fetching the Hebrew-capable model (about 465 MB) — '
        'this one takes a while, once.');
    final model = await _download(modelUrl);
    onStatus?.call('Saving the model…');
    File(modelPath(baseDir)).writeAsBytesSync(model);
    onStatus?.call('Ready. Recordings on this PC become words — in Hebrew '
        'and in English.');
  }

  static Future<Uint8List> _download(String url) async {
    final client = HttpClient();
    try {
      var target = Uri.parse(url);
      // Hugging Face and GitHub both answer with redirects to a CDN.
      for (var hop = 0; hop < 5; hop++) {
        final req = await client.getUrl(target);
        req.followRedirects = false;
        final res = await req.close();
        if (res.statusCode >= 300 && res.statusCode < 400) {
          final loc = res.headers.value(HttpHeaders.locationHeader);
          await res.drain<void>();
          if (loc == null) throw HttpException('redirect without location');
          target = Uri.parse(loc);
          continue;
        }
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode} for $target');
        }
        final chunks = <int>[];
        await for (final c in res) {
          chunks.addAll(c);
        }
        return Uint8List.fromList(chunks);
      }
      throw const HttpException('too many redirects');
    } finally {
      client.close();
    }
  }

  /// Read the words out of a PCM16 WAV.
  ///
  /// [language] is an ISO code ('he', 'en') or 'auto'. Naming the language
  /// beats auto-detection on short, quiet clips — and this app knows which
  /// language its person speaks.
  /// Returns '' when nothing was understood. Throws when the engine is
  /// missing or refuses the file.
  static Future<String> transcribeWav(String baseDir, String wavPath,
      {String language = 'auto'}) async {
    if (!isInstalled(baseDir)) {
      throw StateError('whisper is not installed in $baseDir');
    }
    final res = await Process.run(
      exePath(baseDir),
      [
        '-m', modelPath(baseDir),
        '-f', wavPath,
        '-l', language,
        '-nt', // words only, no timestamps
        '--no-prints', // keep the engine's chatter out of the words
        '-t', '4', // threads: brisk on a laptop, never greedy
      ],
      // RAW BYTES, decoded as UTF-8 by us. Windows' system codepage would
      // turn every Hebrew letter into rubbish — the one mistake that would
      // have made this whole engine look broken again.
      stdoutEncoding: null,
      stderrEncoding: null,
    );
    if (res.exitCode != 0) {
      final err = utf8.decode(res.stderr as List<int>, allowMalformed: true);
      debugPrint('BNS whisper failed (${res.exitCode}): $err');
      throw StateError('whisper exited ${res.exitCode}');
    }
    return utf8
        .decode(res.stdout as List<int>, allowMalformed: true)
        .trim();
  }
}
