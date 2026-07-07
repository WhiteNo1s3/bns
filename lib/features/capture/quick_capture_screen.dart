import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// Full voice + text capture screen.
/// Records using the `record` package, plays back with audioplayers.
/// Saves as QuickCapture (with audioPath) + optional link.
class QuickCaptureScreen extends StatefulWidget {
  final String? linkedRoutineId;
  final String? linkedEventId;
  final String? initialText;
  final List<String>? initialTags; // e.g. ['mad-vent'] from Mad mode
  /// True when arriving from the home-widget 🎤 button: start recording
  /// immediately — one tap from home screen to talking.
  final bool autoRecord;

  const QuickCaptureScreen({
    super.key,
    this.linkedRoutineId,
    this.linkedEventId,
    this.initialText,
    this.initialTags,
    this.autoRecord = false,
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

  MemoryLevel _memoryLevel = MemoryLevel.quick;
  final _contextController =
      TextEditingController(); // for "what happened / why" in remember/memorize
  final Set<String> _selectedTags =
      {}; // for crisis, good, garden tags, search by routine/crisis

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
    }
    if (widget.initialTags != null) {
      _selectedTags.addAll(widget.initialTags!);
    }
    // If linked to a routine, default to "Remember this" to capture what happened
    if (widget.linkedRoutineId != null && _memoryLevel == MemoryLevel.quick) {
      _memoryLevel = MemoryLevel.remember;
    }
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
    if (widget.autoRecord) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoStart());
    }
  }

  /// Widget-initiated capture: the phone gently speaks the subject prompt
  /// first (device engine, skipped in quiet mode), THEN the mic opens —
  /// the spoken prompt never ends up inside the recording.
  Future<void> _autoStart() async {
    if (!mounted || _isRecording) return;
    final settings = await IsarService.getSettings();
    if (!settings.quietMode) {
      await TtsService.speakSubject('Tell me about today.');
    }
    if (mounted && !_isRecording) await _toggleRecording();
  }

  @override
  void dispose() {
    _textController.dispose();
    _contextController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _requestMic() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Microphone permission needed for voice notes.')),
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

      // Voice-optimized: mono AAC at 48 kbps — clear speech at ~1/3 the size
      // of the old 128 kbps default. Small at birth beats compressing later
      // (m4a is already compressed; re-zipping old files gains ~nothing).
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 44100,
          numChannels: 1,
        ),
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

    final tags = ['quick-thought'];
    if (_memoryLevel == MemoryLevel.remember) tags.add('remember-this');
    if (_memoryLevel == MemoryLevel.memorize) tags.add('memorize-this');
    tags.addAll(
        _selectedTags); // include user chosen tags like crisis, good, felt safe etc.

    final capture = QuickCapture(
      id: _uuid.v4(),
      at: DateTime.now(),
      text: text.isEmpty ? null : text,
      audioPath: _audioPath,
      linkedRoutineId: widget.linkedRoutineId,
      linkedEventId: widget.linkedEventId,
      tags: tags,
      memoryLevel: _memoryLevel,
      contextNote: _contextController.text.trim().isEmpty
          ? null
          : _contextController.text.trim(),
    );

    await IsarService.addCapture(capture);

    // Update Android widget
    AndroidBnsWidget.updateWidget();

    if (mounted) {
      final msg = _selectedTags.contains('mad-vent')
          ? 'Vented. It burns away on its own — nothing is held against you.'
          : _memoryLevel == MemoryLevel.memorize
              ? 'Memorized permanently. This will stay with you.'
              : _memoryLevel == MemoryLevel.remember
                  ? 'Remembered. The context of what happened is saved for you.'
                  : 'Saved. Thank you for capturing that.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
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
      appBar: BnsAppBar(
        title: 'Quick thought',
        actions: [
          TextButton(
            onPressed: _saveCapture,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _selectedTags.contains('mad-vent')
                  ? 'Let it out. Curse everyone and everything — only you can see this, and it burns out on its own within about 2 days.'
                  : _memoryLevel == MemoryLevel.memorize
                      ? 'Capture this permanently. The day and what happened will be remembered.'
                      : _memoryLevel == MemoryLevel.remember
                          ? 'Remember this moment. Note what happened in the routine or day for later recall.'
                          : 'Say or write anything. No judgment, just capture.',
              style: const TextStyle(fontSize: 16),
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
                        ? [
                            BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 24,
                                spreadRadius: 4)
                          ]
                        : null,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 64,
                    color: _isRecording
                        ? Colors.white
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _isRecording
                    ? 'Recording… ${_formatDuration(_recordDuration)} — tap to stop'
                    : (hasAudio
                        ? 'Tap mic to record again'
                        : 'Tap to start recording'),
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
                    icon: Icon(_isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled),
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

            // Memory level selector - "remember this" vs "memorize this" vs quick
            const SizedBox(height: 16),
            const Text('How important is this memory?',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<MemoryLevel>(
              segments: const [
                ButtonSegment(
                    value: MemoryLevel.quick,
                    label: Text('Quick note'),
                    icon: Icon(Icons.note)),
                ButtonSegment(
                    value: MemoryLevel.remember,
                    label: Text('Remember this'),
                    icon: Icon(Icons.bookmark)),
                ButtonSegment(
                    value: MemoryLevel.memorize,
                    label: Text('Memorize permanently'),
                    icon: Icon(Icons.stars)),
              ],
              selected: {_memoryLevel},
              onSelectionChanged: (newSelection) {
                setState(() => _memoryLevel = newSelection.first);
              },
            ),

            // Tags for search, crisis, garden organization (good, felt safe, crisis etc.)
            const SizedBox(height: 12),
            const Text(
                'Tags (search by routine/crisis, visual garden, share with doctors):',
                style: TextStyle(fontSize: 12)),
            Wrap(
              spacing: 4,
              children: {
                'crisis',
                'good',
                'felt safe',
                'felt confused',
                'felt out of bound',
                'drama',
                'wonderings',
                'routine',
                ..._selectedTags
              }.map((tag) {
                final selected = _selectedTags.contains(tag);
                return FilterChip(
                  label: Text(tag),
                  selected: selected,
                  onSelected: (s) {
                    setState(() {
                      if (s)
                        _selectedTags.add(tag);
                      else
                        _selectedTags.remove(tag);
                    });
                  },
                );
              }).toList(),
            ),

            // Context note for remember/memorize - "what happened / why the crisis"
            if (_memoryLevel != MemoryLevel.quick) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _contextController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText:
                      'What happened? Why? (context for this day/routine)',
                  hintText:
                      'e.g. Felt overwhelmed after the call, routine triggered anxiety',
                  border: OutlineInputBorder(),
                  helperText:
                      'This helps memorize the "why" and the day itself',
                ),
              ),
            ],

            // Text
            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: _memoryLevel == MemoryLevel.quick
                    ? 'Or type a quick note here…'
                    : 'Additional thoughts...',
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
