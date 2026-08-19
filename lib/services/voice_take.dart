import 'dart:io' show Directory, File, Platform;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// ONE MICROPHONE, ONE PERSON.
///
/// Two recorders on one phone is not a feature, it is a silence: the second
/// one fails, and the person only learns that the button did nothing. Every
/// place in BNS that records — the capture room's takes, the mic beside any
/// text field — comes through here, so the mic can only ever be held by one
/// of them, and whoever holds it can be named.
///
/// Nothing here listens on its own or stops on its own. A take runs from the
/// press that starts it to the press that ends it — a finger landing
/// anywhere else on the screen changes nothing (owner, 2026-08-19: the whole
/// reason the borrowed popup was not good enough).
class VoiceTake {
  VoiceTake._();

  static final AudioRecorder _rec = AudioRecorder();
  static const _uuid = Uuid();

  /// Who is holding the mic ('capture', 'field', …) — null when it is free.
  static String? _holder;
  static String? _path;
  static DateTime? _startedAt;

  static bool get isRecording => _holder != null;

  /// The name of whoever holds the mic right now, for doors that must gray
  /// themselves out instead of failing when pressed.
  static String? get holder => _holder;

  /// How long the running take has been going.
  static Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  /// Desktops record WAV so every ear can read the file without a codec;
  /// phones stay on small AAC (a long vent should not cost a gigabyte).
  static bool get _desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// The recorder itself asks the OS. Never permission_handler here — that
  /// plugin has no macOS implementation, so request() threw and the mic
  /// never opened, and macOS never showed its permission sheet.
  static Future<bool> ensureMic() async {
    try {
      return await _rec.hasPermission(request: true);
    } catch (_) {
      return false;
    }
  }

  /// Open the mic for [holder]. Returns the path being recorded to, or null
  /// when the mic could not open (no permission, someone else holds it, or
  /// the device refused).
  ///
  /// [dir] is where the file lands; a field's throwaway dictation passes the
  /// temp folder, the capture room passes its own audio folder.
  static Future<String?> start({
    required String holder,
    required Directory dir,
    String prefix = 'take',
  }) async {
    if (isRecording) return null; // the mic is taken — never two
    if (!await ensureMic()) return null;
    final path = p.join(
      dir.path,
      '${prefix}_${_uuid.v4().substring(0, 8)}.${_desktop ? 'wav' : 'm4a'}',
    );
    try {
      await _rec.start(
        _desktop
            ? const RecordConfig(
                encoder: AudioEncoder.wav,
                sampleRate: 16000,
                numChannels: 1,
              )
            : const RecordConfig(
                encoder: AudioEncoder.aacLc,
                bitRate: 48000,
                sampleRate: 44100,
                numChannels: 1,
              ),
        path: path,
      );
    } catch (e) {
      debugPrint('BNS mic did not open: $e');
      return null;
    }
    _holder = holder;
    _path = path;
    _startedAt = DateTime.now();
    return path;
  }

  /// Close the mic and hand back the finished file. Null when nothing was
  /// recording, or the platform gave nothing back.
  static Future<String?> stop() async {
    if (!isRecording) return null;
    String? path;
    try {
      path = await _rec.stop() ?? _path;
    } catch (e) {
      debugPrint('BNS mic did not stop cleanly: $e');
      path = _path;
    }
    _holder = null;
    _path = null;
    _startedAt = null;
    return path;
  }

  /// Stop and throw the file away (the person left, or changed their mind).
  static Future<void> cancel() async {
    final path = await stop();
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// A dictation that already became words leaves nothing behind.
  static Future<void> discard(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  /// Where a throwaway field dictation lives until its words land.
  static Future<Directory> scratchDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'dictation'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }
}
