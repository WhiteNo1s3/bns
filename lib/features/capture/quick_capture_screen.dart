import 'dart:async';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/stt_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';

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
  Timer? _durationTimer;

  /// Live speech-to-text while recording ("STT all the time"). The transcript
  /// is saved WITH the voice note and travels inside the .bns, so a voice
  /// to-do is readable text everywhere — app, family Explorer, other devices.
  String _liveTranscript = '';
  bool _sttActive = false;

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
    _durationTimer?.cancel();
    if (_sttActive) SttService.stop();
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
      // Stop recording — and close the live transcript with it.
      final path = await _audioRecorder.stop();
      _durationTimer?.cancel();
      String transcript = _liveTranscript;
      if (_sttActive) {
        transcript = await SttService.stop();
        _sttActive = false;
      }
      setState(() {
        _isRecording = false;
        _audioPath = path;
        _liveTranscript = transcript;
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
        _liveTranscript = '';
      });

      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording && mounted) {
          setState(() => _recordDuration += const Duration(seconds: 1));
        }
      });

      // Live transcript alongside the recording. The recorder always comes
      // first: on devices where the speech engine can't share the mic, STT
      // just fails quietly and the voice note still records perfectly.
      final settings = await IsarService.getSettings();
      if (settings.sttEnabled && _isRecording) {
        _sttActive = await SttService.start(
          localeId: settings.sttLocale,
          onText: (text) {
            if (mounted) setState(() => _liveTranscript = text);
          },
          onState: (s) {
            if (s == SttState.unavailable && mounted) {
              setState(() => _sttActive = false);
            }
          },
        );
        if (mounted) setState(() {});
      }
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
    final transcript = _liveTranscript.trim();
    if (text.isEmpty && _audioPath == null && transcript.isEmpty) {
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
      // A voice-only thought still saves readable words: the transcript
      // stands in as the text when nothing was typed.
      text: text.isNotEmpty
          ? text
          : (transcript.isNotEmpty ? transcript : null),
      audioPath: _audioPath,
      transcript: transcript.isEmpty ? null : transcript,
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

            // Live transcript while talking — your words appearing as text.
            if (_isRecording && _sttActive) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.graphic_eq,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _liveTranscript.isEmpty
                              ? 'Listening… your words will appear here.'
                              : _liveTranscript,
                          style: TextStyle(
                            fontStyle: _liveTranscript.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Playback (+ what the device engine understood, editable-adjacent:
            // the transcript is also placed in the text flow on save)
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
                  subtitle: Text(
                    _liveTranscript.trim().isNotEmpty
                        ? '“${_liveTranscript.trim()}”'
                        : p.basename(_audioPath!),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() {
                        // Transcript belongs to the recording — goes with it.
                        _audioPath = null;
                        _liveTranscript = '';
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
            // 'family' is special: tagged items enter the family share file —
            // sharing a moment is always the person's own choice, one tap.
            const SizedBox(height: 12),
            const Text(
                'Tags (search by routine/crisis, visual garden, share with doctors; '
                '"family" puts this moment into the family file):',
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
                'family',
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
                decoration: InputDecoration(
                  labelText:
                      'What happened? Why? (context for this day/routine)',
                  hintText:
                      'e.g. Felt overwhelmed after the call, routine triggered anxiety',
                  border: const OutlineInputBorder(),
                  helperText:
                      'This helps memorize the "why" and the day itself',
                  suffixIcon:
                      DictationMicButton(controller: _contextController),
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
                    ? 'Or type a quick note here… (tap the small mic to speak it)'
                    : 'Additional thoughts...',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                suffixIcon: DictationMicButton(controller: _textController),
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
