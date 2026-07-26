import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';

/// The open-source ear (owner, 2026-07-26: "we add this open source program
/// into ours — in Windows there is no other choice").
///
/// Vosk (Apache-2.0, alphacephei) — fully offline speech recognition with
/// small per-language models. No cloud, no accounts, no ads, free forever:
/// the same rules as the rest of BNS. This service binds libvosk directly
/// over FFI and turns recorded WAV voice notes into readable words.
///
/// Layout on disk (inside the app's own folder, never system-wide):
///   <baseDir>/libvosk.dll (+ its companion DLLs)
///   <baseDir>/model/      (one unpacked Vosk model)
class VoskService {
  VoskService._();

  /// Official sources — the Vosk project's own release artifacts.
  static const engineUrl =
      'https://github.com/alphacep/vosk-api/releases/download/v0.3.45/vosk-win64-0.3.45.zip';
  static const modelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip';

  /// True when both the engine and a model are unpacked under [baseDir].
  static bool isInstalled(String baseDir) {
    return File('$baseDir\\libvosk.dll').existsSync() &&
        Directory('$baseDir\\model').existsSync();
  }

  /// Download + unpack the engine and the small English model into
  /// [baseDir]. ~7 MB + ~40 MB, one time, from the project's official
  /// links. [onStatus] narrates progress for the settings screen.
  static Future<void> install(String baseDir,
      {void Function(String status)? onStatus}) async {
    final dir = Directory(baseDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    onStatus?.call('Fetching the engine (about 7 MB)…');
    final engineZip = await _download(engineUrl);
    onStatus?.call('Unpacking the engine…');
    // The zip holds vosk-win64-<v>/ with libvosk.dll and companions — the
    // DLLs land flat in baseDir so the loader finds them side by side.
    for (final f in ZipDecoder().decodeBytes(engineZip).files) {
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      if (!name.toLowerCase().endsWith('.dll')) continue;
      File('$baseDir\\$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.content as List<int>);
    }

    onStatus?.call('Fetching the language model (about 40 MB)…');
    final modelZip = await _download(modelUrl);
    onStatus?.call('Unpacking the model…');
    final modelDir = Directory('$baseDir\\model');
    if (modelDir.existsSync()) modelDir.deleteSync(recursive: true);
    for (final f in ZipDecoder().decodeBytes(modelZip).files) {
      if (!f.isFile) continue;
      // Strip the top-level "vosk-model-small-…/" folder.
      final parts = f.name.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) continue;
      final rel = parts.sublist(1).join('\\');
      File('${modelDir.path}\\$rel')
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.content as List<int>);
    }
    onStatus?.call('Ready. Voice notes can become words on this PC.');
  }

  static Future<Uint8List> _download(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode} for $url');
      }
      final chunks = <int>[];
      await for (final c in res) {
        chunks.addAll(c);
      }
      return Uint8List.fromList(chunks);
    } finally {
      client.close();
    }
  }

  /// Transcribe a PCM16 WAV file. Runs in its own isolate so the UI never
  /// stutters; each call opens its own engine handle (safe and simple —
  /// voice notes are short). Returns '' when nothing was understood.
  /// Throws [StateError] when the engine/model/WAV are unusable.
  static Future<String> transcribeWav(String baseDir, String wavPath) {
    return Isolate.run(() => _transcribeSync(baseDir, wavPath));
  }

  static String _transcribeSync(String baseDir, String wavPath) {
    final wav = _readWav(wavPath);

    final lib = DynamicLibrary.open('$baseDir\\libvosk.dll');
    final setLogLevel = lib.lookupFunction<Void Function(Int32),
        void Function(int)>('vosk_set_log_level');
    final modelNew = lib.lookupFunction<Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)>('vosk_model_new');
    final modelFree = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('vosk_model_free');
    final recNew = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Void>, Float),
        Pointer<Void> Function(Pointer<Void>, double)>('vosk_recognizer_new');
    final recFree = lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('vosk_recognizer_free');
    final recAccept = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
        int Function(
            Pointer<Void>, Pointer<Uint8>, int)>('vosk_recognizer_accept_waveform');
    final recResult = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('vosk_recognizer_result');
    final recFinal = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('vosk_recognizer_final_result');

    setLogLevel(-1); // the engine's chatter belongs to the engine

    final modelPath = '$baseDir\\model'.toNativeUtf8();
    final model = modelNew(modelPath);
    malloc.free(modelPath);
    if (model == nullptr) {
      throw StateError('Vosk model failed to load from $baseDir\\model');
    }

    final rec = recNew(model, wav.sampleRate.toDouble());
    if (rec == nullptr) {
      modelFree(model);
      throw StateError('Vosk recognizer failed to start');
    }

    final pieces = <String>[];
    String textOf(Pointer<Utf8> jsonPtr) {
      try {
        return (jsonDecode(jsonPtr.toDartString())
                    as Map<String, dynamic>)['text'] as String? ??
            '';
      } catch (_) {
        return '';
      }
    }

    const chunkSize = 8000; // bytes — ~0.25 s of 16 kHz PCM16
    final buf = malloc.allocate<Uint8>(chunkSize);
    try {
      for (var off = 0; off < wav.pcm.length; off += chunkSize) {
        final len = (off + chunkSize > wav.pcm.length)
            ? wav.pcm.length - off
            : chunkSize;
        buf.asTypedList(chunkSize).setRange(0, len, wav.pcm, off);
        if (recAccept(rec, buf, len) == 1) {
          final t = textOf(recResult(rec));
          if (t.isNotEmpty) pieces.add(t);
        }
      }
      final t = textOf(recFinal(rec));
      if (t.isNotEmpty) pieces.add(t);
    } finally {
      malloc.free(buf);
      recFree(rec);
      modelFree(model);
    }
    return pieces.join(' ').trim();
  }

  /// Minimal RIFF/WAV reader: PCM16 only (which is what our recorder
  /// writes). Anything else says so instead of producing garbage.
  static ({Uint8List pcm, int sampleRate}) _readWav(String path) {
    final bytes = File(path).readAsBytesSync();
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw StateError('Not a WAV file: $path');
    }
    final data = ByteData.sublistView(bytes);
    var off = 12;
    int? sampleRate;
    int? bitsPerSample;
    int? channels;
    while (off + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(off, off + 4));
      final size = data.getUint32(off + 4, Endian.little);
      final body = off + 8;
      if (id == 'fmt ') {
        final format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
        if (format != 1 || bitsPerSample != 16) {
          throw StateError('Only PCM16 WAV is supported (got format '
              '$format, $bitsPerSample bits)');
        }
      } else if (id == 'data') {
        if (sampleRate == null) break;
        var pcm = bytes.sublist(
            body, (body + size).clamp(0, bytes.length));
        // Downmix stereo to mono if a foreign file wanders in.
        if (channels == 2) {
          final mono = Uint8List(pcm.length ~/ 2);
          final src = ByteData.sublistView(pcm);
          final dst = ByteData.sublistView(mono);
          for (var i = 0, j = 0; i + 4 <= pcm.length; i += 4, j += 2) {
            final l = src.getInt16(i, Endian.little);
            final r = src.getInt16(i + 2, Endian.little);
            dst.setInt16(j, ((l + r) ~/ 2), Endian.little);
          }
          pcm = mono;
        }
        return (pcm: pcm, sampleRate: sampleRate);
      }
      off = body + size + (size.isOdd ? 1 : 0);
    }
    throw StateError('WAV has no readable data chunk: $path');
  }
}
