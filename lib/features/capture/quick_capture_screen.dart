import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/services/vosk_service.dart';
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

  /// Transcript of the voice note, when one exists. Live STT-while-recording
  /// was removed (owner's phone, 2026-07-26): the speech engine stole the mic
  /// and the recording died. The field stays — transcripts still travel in
  /// .bns and can come from platforms/engines that CAN share the mic.
  String _liveTranscript = '';

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
      await TtsService.speakSubject(
          L.t('Tell me about today.', 'ספרו לי על היום.'));
    }
    if (mounted && !_isRecording) await _toggleRecording();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
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
          SnackBar(
              content: Text(L.t(
                  'Microphone permission needed for voice notes.',
                  'צריך הרשאת מיקרופון בשביל הקלטות קוליות.'))),
        );
      }
    }
  }

  Future<void> _toggleRecording() async {
    await _requestMic();

    // On Windows the recording is WAV so the open-source ear (Vosk) can
    // read words straight out of the file afterwards — sequential, honest,
    // no mic fights ever.
    final desktopStt = Platform.isWindows;

    if (_isRecording) {
      final path = await _audioRecorder.stop();
      _durationTimer?.cancel();
      setState(() {
        _isRecording = false;
        _audioPath = path;
      });
      if (desktopStt && path != null) _transcribeWithVosk(path);
    } else {
      // Start recording
      final dir = await IsarService.getAudioDir();
      final fileName =
          'cap_${_uuid.v4().substring(0, 8)}.${desktopStt ? 'wav' : 'm4a'}';
      final path = p.join(dir.path, fileName);

      final canRecord = await _audioRecorder.hasPermission();
      if (!canRecord) return;

      // Voice-optimized: mono AAC at 48 kbps — clear speech at ~1/3 the size
      // of the old 128 kbps default. Small at birth beats compressing later
      // (m4a is already compressed; re-zipping old files gains ~nothing).
      // Windows: PCM16 WAV at 16 kHz — exactly what Vosk reads.
      await _audioRecorder.start(
        desktopStt
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

      // FIELD TRUTH (owner's phone, 2026-07-26): the recorder and the speech
      // engine CANNOT share one microphone on Android — running both killed
      // the recording itself (a tiny silent file that ends instantly).
      // Recording gets the mic to itself now. Words come by typing or by
      // the dictation mic AFTER the voice is safely kept — and on Windows,
      // Vosk reads them out of the finished file automatically.
    }
  }

  /// The chaos, decrypted: after a Windows recording lands, the offline
  /// open-source engine reads words out of the WAV. Quietly skipped when
  /// the engine isn't installed (Settings offers it) or nothing was heard.
  Future<void> _transcribeWithVosk(String wavPath) async {
    try {
      final support = await getApplicationSupportDirectory();
      final voskDir = p.join(support.path, 'vosk');
      if (!VoskService.isInstalled(voskDir)) return;
      final text = await VoskService.transcribeWav(voskDir, wavPath);
      if (text.isEmpty || !mounted) return;
      setState(() => _liveTranscript = text);
    } catch (_) {
      // The recording is already safe — words are a bonus, never a blocker.
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
          ? L.t(
              'Vented. It burns away on its own — nothing is held against you.',
              'פרקת. זה נמחק מעצמו — שום דבר לא נשמר נגדך.')
          : _memoryLevel == MemoryLevel.memorize
              ? L.t('Memorized permanently. This will stay with you.',
                  'נשמר לתמיד. זה יישאר איתך.')
              : _memoryLevel == MemoryLevel.remember
                  ? L.t(
                      'Remembered. The context of what happened is saved for you.',
                      'נשמר לזיכרון. ההקשר של מה שקרה נשמר בשבילך.')
                  : L.t('Saved. Thank you for capturing that.',
                      'נשמר. תודה שתיעדת את זה.');
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
        title: L.t('Quick thought', 'מחשבה מהירה'),
        actions: [
          TextButton(
            onPressed: _saveCapture,
            child: Text(L.t('Save', 'שמירה'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      // The whole screen SCROLLS (owner's phone, 2026-07-26: the tag chips
      // sat 300px past the bottom behind an overflow stripe). A capture
      // screen holds recording + transcript + tags + notes — on a phone
      // with a keyboard up, that is taller than any screen. Never a
      // fixed-height Column again.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _selectedTags.contains('mad-vent')
                  ? L.t(
                      'Let it out. Curse everyone and everything — only you can see this, and it burns out on its own within about 2 days.',
                      'להוציא הכול. אפשר לקלל את כולם ואת הכול — רק העיניים שלך רואות את זה, וזה נמחק מעצמו תוך יומיים בערך.')
                  : _memoryLevel == MemoryLevel.memorize
                      ? L.t(
                          'Capture this permanently. The day and what happened will be remembered.',
                          'לשמור את זה לתמיד. היום ומה שקרה בו יישמרו בזיכרון.')
                      : _memoryLevel == MemoryLevel.remember
                          ? L.t(
                              'Remember this moment. Note what happened in the routine or day for later recall.',
                              'לזכור את הרגע הזה. אפשר לרשום מה קרה בשגרה או ביום — לשליפה אחר כך.')
                          : L.t('Say or write anything. No judgment, just capture.',
                              'אפשר להגיד או לכתוב כל דבר. בלי שיפוט, רק לתעד.'),
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
                    ? L.t(
                        'Recording… ${_formatDuration(_recordDuration)} — tap to stop',
                        'מקליט… ${_formatDuration(_recordDuration)} — הקשה לעצירה')
                    : (hasAudio
                        ? L.t('Tap mic to record again',
                            'הקשה על המיקרופון להקלטה נוספת')
                        : L.t('Tap to start recording',
                            'הקשה כדי להתחיל להקליט')),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            // While recording, the mic belongs to the recording — honestly.
            // (Live transcription fought the recorder for the mic and the
            // recording lost. Never again.)
            if (_isRecording) ...[
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
                          L.t(
                              'Your voice is being kept. After you stop, words '
                              'can be typed — or spoken into text with the '
                              'little mic by the text box.',
                              'הקול שלך נשמר. אחרי העצירה אפשר להקליד מילים — '
                              'או לדבר אותן לתוך הטקסט עם המיקרופון הקטן '
                              'שליד תיבת הטקסט.'),
                          style: const TextStyle(fontStyle: FontStyle.italic),
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
                  title: Text(L.t('Voice note', 'הקלטה קולית')),
                  // The words WRAP — a transcript carries meaning, so it is
                  // never cut off with an ellipsis. No words at all is said
                  // honestly, never a raw file name.
                  subtitle: Text(
                    _liveTranscript.trim().isNotEmpty
                        ? '“${_liveTranscript.trim()}”'
                        : L.t('A voice-only moment (no words yet)',
                            'רגע קולי בלבד (עדיין בלי מילים)'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The app reads the transcript back — hear your own
                      // words, relaxed, before saving.
                      if (_liveTranscript.trim().isNotEmpty)
                        IconButton(
                          tooltip: L.t('Hear it read aloud', 'להקריא בקול'),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.volume_up),
                          onPressed: () =>
                              TtsService.speak(_liveTranscript.trim()),
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          setState(() {
                            // Transcript belongs to the recording — goes
                            // with it.
                            _audioPath = null;
                            _liveTranscript = '';
                            _isPlaying = false;
                          });
                          _audioPlayer.stop();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Memory level selector - "remember this" vs "memorize this" vs quick
            const SizedBox(height: 16),
            Text(L.t('How important is this memory?', 'כמה חשוב הזיכרון הזה?'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<MemoryLevel>(
              segments: [
                ButtonSegment(
                    value: MemoryLevel.quick,
                    label: Text(L.t('Quick note', 'פתק מהיר')),
                    icon: const Icon(Icons.note)),
                ButtonSegment(
                    value: MemoryLevel.remember,
                    label: Text(L.t('Remember this', 'לזכור את זה')),
                    icon: const Icon(Icons.bookmark)),
                ButtonSegment(
                    value: MemoryLevel.memorize,
                    label: Text(L.t('Memorize permanently', 'לשמור לתמיד')),
                    icon: const Icon(Icons.stars)),
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
            Text(
                L.t(
                    'Tags (search by routine/crisis, visual garden, share with doctors; '
                    '"family" puts this moment into the family file):',
                    'תגיות (חיפוש לפי שגרה/משבר, גינה חזותית, שיתוף עם רופאים; '
                    '"family" מכניסה את הרגע הזה לקובץ המשפחתי):'),
                style: const TextStyle(fontSize: 12)),
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
                  labelText: L.t(
                      'What happened? Why? (context for this day/routine)',
                      'מה קרה? למה? (הקשר ליום/לשגרה)'),
                  hintText: L.t(
                      'e.g. Felt overwhelmed after the call, routine triggered anxiety',
                      'למשל: הצפה אחרי השיחה, השגרה עוררה חרדה'),
                  border: const OutlineInputBorder(),
                  helperText: L.t(
                      'This helps memorize the "why" and the day itself',
                      'זה עוזר לזכור את ה"למה" ואת היום עצמו'),
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
                    ? L.t(
                        'Or type a quick note here… (tap the small mic to speak it)',
                        'או להקליד כאן פתק מהיר… (הקשה על המיקרופון הקטן כדי לדבר)')
                    : L.t('Additional thoughts...', 'מחשבות נוספות...'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                suffixIcon: DictationMicButton(controller: _textController),
              ),
            ),

            const SizedBox(height: 24),

            // Save + cancel
            FilledButton.icon(
              onPressed: _saveCapture,
              icon: const Icon(Icons.check),
              label: Text(L.t('Save this thought', 'לשמור את המחשבה הזאת')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('Cancel (nothing saved)', 'ביטול (שום דבר לא נשמר)')),
            ),
          ],
        ),
      ),
    );
  }
}
