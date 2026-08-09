import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

import 'package:bns/data/local/isar_service.dart';

/// One small player for every "hear it again" in the app (owner, 2026-07-26:
/// the player must PLAY — the snackbar placeholders made recordings a closed
/// book). Tap plays; tapping the same memory again stops it. A missing file
/// says so honestly instead of pretending.
class AudioPlaybackService {
  AudioPlaybackService._();

  static final AudioPlayer _player = AudioPlayer();
  static String? _playingPath;

  /// Plays [path], or stops if [path] is already playing.
  /// Returns true when now playing, false when this call stopped it.
  /// Throws [FileSystemException] when the file is gone.
  ///
  /// [path] may be a dead absolute path from another machine — captures
  /// carry them across devices. resolveAudioPath finds the same filename
  /// in the current audio folder, so a memory keeps its voice after a
  /// sync, an import, or a home move. Identity (play/stop toggling)
  /// stays keyed on the STORED path the screens know.
  static Future<bool> toggle(String path) async {
    if (_playingPath == path) {
      await _player.stop();
      _playingPath = null;
      return false;
    }
    await _player.stop();
    final resolved = await IsarService.resolveAudioPath(path);
    if (resolved == null) {
      _playingPath = null;
      throw FileSystemException('audio file missing', path);
    }
    _playingPath = path;
    await _player.play(DeviceFileSource(resolved));
    _player.onPlayerComplete.first.then((_) {
      if (_playingPath == path) _playingPath = null;
    });
    return true;
  }

  static Future<void> stopAll() async {
    await _player.stop();
    _playingPath = null;
  }

  static bool isPlaying(String path) => _playingPath == path;
}
