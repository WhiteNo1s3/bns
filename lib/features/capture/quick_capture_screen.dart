import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';

/// Full voice + text capture screen.
/// Records using the `record` package, plays back with audioplayers.
/// Saves as QuickCapture (with audioPath) + optional link.
class QuickCaptureScreen extends StatefulWidget {
  final String? linkedRoutineId;
  final String? linkedEventId;
  final String? initialText;

  const QuickCaptureScreen({
    super.key,
    this.linkedRoutineId,
    this.linkedEventId,
    this.initialText,
  });

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final _textController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _uuid = const Uuid();

  String? _audioPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  Duration _recordDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
    }
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _requestMic() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission needed for voice notes.')),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    await _requestMic();

    if (_isRecording) {
      // Stop recording
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });
    } else {
      // Start recording
      final dir = await IsarService.getAudioDir();
      final fileName = 'cap_${_uuid.v4().substring(0, 8)}.m4a';
      final path = p.join(dir.path, fileName);

      final canRecord = await _audioRecorder.hasPermission();
      if (!canRecord) return;

      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _audioPath = null;
        _recordDuration = Duration.zero;
      });

      // Simple duration ticker
      Future.doWhile(() async {
        await Future.delayed(const Duration(seconds: 1));
        if (_isRecording && mounted) {
          setState(() => _recordDuration += const Duration(seconds: 1));
          return true;
        }
        return false;
      });
    }
  }

  Future<void> _playPauseAudio() async {
    if (_audioPath == null) return;

    if (_isPlaying) {
      await _audioPlayer.pause();
      setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(_audioPath!));
      setState(() => _isPlaying = true);
    }
  }

  Future<void> _saveCapture() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _audioPath == null) {
      Navigator.pop(context);
      return;
    }

    final capture = QuickCapture(
      id: _uuid.v4(),
      at: DateTime.now(),
      text: text.isEmpty ? null : text,
      audioPath: _audioPath,
      linkedRoutineId: widget.linkedRoutineId,
      linkedEventId: widget.linkedEventId,
      tags: ['quick-thought'],
    );

    await IsarService.addCapture(capture);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved. Thank you for capturing that.')),
      );
      Navigator.pop(context, true); // return true to indicate saved
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final hasAudio = _audioPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quick thought'),
        actions: [
          TextButton(
            onPressed: _saveCapture,
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Say or write anything. No judgment, just capture.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),

            // Big friendly record button
            Center(
              child: GestureDetector(
                onTap: _toggleRecording,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? Colors.red.shade400
                        : Theme.of(context).colorScheme.primaryContainer,
                    boxShadow: _isRecording
                        ? [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 24, spreadRadius: 4)]
                        : null,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 64,
                    color: _isRecording ? Colors.white : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _isRecording
                    ? 'Recording… ${_formatDuration(_recordDuration)} — tap to stop'
                    : (hasAudio ? 'Tap mic to record again' : 'Tap to start recording'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Playback
            if (hasAudio) ...[
              Card(
                child: ListTile(
                  leading: IconButton(
                    iconSize: 36,
                    icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                    onPressed: _playPauseAudio,
                  ),
                  title: const Text('Voice note'),
                  subtitle: Text(p.basename(_audioPath!)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() {
                        _audioPath = null;
                        _isPlaying = false;
                      });
                      _audioPlayer.stop();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Text
            TextField(
              controller: _textController,
              maxLines: 5,
              minLines: 3,
              decoration: InputDecoration(
                hintText: 'Or type a quick note here…',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),

            const Spacer(),

            // Save + cancel
            FilledButton.icon(
              onPressed: _saveCapture,
              icon: const Icon(Icons.check),
              label: const Text('Save this thought'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel (nothing saved)'),
            ),
          ],
        ),
      ),
    );
  }
}

