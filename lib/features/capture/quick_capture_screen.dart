import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/recording_text.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/apple_file_stt.dart';
import 'package:bns/services/speech_popup.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/services/vosk_service.dart';
import 'package:bns/services/whisper_service.dart';
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
  /// Calendar day this idea is for (YYYY-MM-DD). Tonight's bag for tomorrow.
  final String? forDate;

  const QuickCaptureScreen({
    super.key,
    this.linkedRoutineId,
    this.linkedEventId,
    this.initialText,
    this.initialTags,
    this.autoRecord = false,
    this.forDate,
  });

  @override
  State<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends State<QuickCaptureScreen> {
  final _textController = TextEditingController();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  final _uuid = const Uuid();

  bool _isRecording = false;
  bool _isPlaying = false;
  bool _hearingWords = false;
  Duration _recordDuration = Duration.zero;
  Timer? _durationTimer;

  /// Finished takes this visit — voice kept, words land in the box.
  final List<_Take> _takes = [];
  String? _playingPath;

  /// Every kept thought is a memory. "Quick" used to hide it after Save.
  MemoryLevel _memoryLevel = defaultKeptLevel;
  bool _showMore = false;
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
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
      }
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
    TtsService.stop();
    _textController.dispose();
    _contextController.dispose();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// The recorder itself asks the OS. Never permission_handler here —
  /// that plugin has no macOS implementation, so request() threw and the
  /// mic never opened, and macOS never showed its permission sheet.
  Future<bool> _ensureMic() async {
    try {
      final allowed = await _audioRecorder.hasPermission(request: true);
      if (allowed) return true;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t(
            'The microphone did not open. You can write it instead.',
            'המיקרופון לא נפתח. אפשר לכתוב במקום.')),
      ));
    }
    return false;
  }

  Future<void> _toggleRecording() async {
    // Desktop (Mac included) records WAV so the file is simple and the
    // open-source ear can read it later. Phones stay on small AAC.
    final desktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    if (_isRecording) {
      try {
        final path = await _audioRecorder.stop();
        _durationTimer?.cancel();
        if (!mounted) return;
        setState(() => _isRecording = false);
        if (path != null) await _keepTake(path);
      } catch (_) {
        _durationTimer?.cancel();
        if (mounted) setState(() => _isRecording = false);
      }
      return;
    }

    final allowed = await _ensureMic();
    if (!allowed || !mounted) return;

    try {
      final dir = await IsarService.getAudioDir();
      final fileName =
          'cap_${_uuid.v4().substring(0, 8)}.${desktop ? 'wav' : 'm4a'}';
      final path = p.join(dir.path, fileName);

      await _audioRecorder.start(
        desktop
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

      await _audioPlayer.stop();
      await TtsService.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _isPlaying = false;
        _playingPath = null;
        _recordDuration = Duration.zero;
      });

      _durationTimer?.cancel();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_isRecording && mounted) {
          setState(() => _recordDuration += const Duration(seconds: 1));
        }
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'The microphone did not open. You can write it instead.',
              'המיקרופון לא נפתח. אפשר לכתוב במקום.')),
        ));
      }
    }
  }

  /// Voice is already safe. Words land in the box under "הקלטה N".
  Future<void> _keepTake(String path) async {
    final n = _takes.length + 1;
    setState(() {
      _takes.add(_Take(n, path, ''));
      _hearingWords = true;
    });
    final heard = await _hearWords(path);
    if (!mounted) return;
    // Remember what was heard for this take (the voice was already kept
    // the moment recording stopped — words only ever add to it).
    final i = _takes.indexWhere((t) => t.path == path);
    if (i != -1) _takes[i] = _Take(_takes[i].number, path, heard);
    final label = recordingLabel(n, hebrew: L.isHebrew);
    final next = appendRecordingBlock(
      current: _textController.text,
      label: label,
      transcript: heard,
    );
    _textController.text = next;
    _textController.selection =
        TextSelection.collapsed(offset: next.length);
    setState(() => _hearingWords = false);
  }

  /// Hebrew first: Apple on-device ear, then Whisper (Windows), then Vosk.
  Future<String> _hearWords(String path) async {
    try {
      if (AppleFileStt.isSupported) {
        final locale = L.isHebrew ? 'he-IL' : 'en-US';
        final apple = await AppleFileStt.transcribeFile(path, locale: locale);
        if (apple.isNotEmpty) return apple;
      }
      final support = await getApplicationSupportDirectory();
      final whisperDir = p.join(support.path, 'whisper');
      if (WhisperService.isInstalled(whisperDir)) {
        final heard = await WhisperService.transcribeWav(
          whisperDir,
          path,
          language: L.isHebrew ? 'he' : 'auto',
        );
        if (heard.trim().isNotEmpty) return heard.trim();
      }
      final voskDir = p.join(support.path, 'vosk');
      if (VoskService.isInstalled(voskDir)) {
        final text = await VoskService.transcribeWav(voskDir, path);
        if (text.trim().isNotEmpty) return text.trim();
      }
    } catch (_) {}
    return '';
  }

  /// ANDROID HAS NO FILE EAR — and Android is the flagship.
  ///
  /// Apple reads the finished recording; Windows has Whisper/Vosk. Android
  /// has neither, and the recorder and the speech engine cannot share one
  /// microphone (field truth, 2026-07-26 — running both killed the
  /// recording). So the words come through the same door Waze uses: the
  /// system popup, AFTER the voice is safely kept. Saying it a second time
  /// is a real cost, so it is offered plainly and never demanded — the
  /// voice is already saved either way, and typing always works.
  bool get _canSpeakWords =>
      SpeechPopup.isSupported &&
      !_isRecording &&
      !_hearingWords &&
      _takes.isNotEmpty &&
      _takes.last.heard.isEmpty;

  Future<void> _speakWordsForLastTake() async {
    final settings = await IsarService.getSettings();
    if (!settings.sttEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'Voice typing is turned off in Settings. Typing works as always.',
              'הקלדה קולית כבויה בהגדרות. הקלדה רגילה עובדת כמו תמיד.')),
        ));
      }
      return;
    }
    final chosen = settings.sttLocale.trim();
    final words = await SpeechPopup.recognize(
      locale: chosen.isEmpty
          ? (L.isHebrew ? 'he-IL' : 'en-US')
          : chosen.replaceAll('_', '-'),
      prompt: L.t('Speak now', 'אפשר לדבר עכשיו'),
    );
    if (!mounted) return;
    final said = (words ?? '').trim();
    if (said.isEmpty) return;
    // The words belong to the take that is waiting for them, and land at
    // the end of the box — right under its own "הקלטה N" line.
    final i = _takes.length - 1;
    if (i >= 0) {
      _takes[i] = _Take(_takes[i].number, _takes[i].path, said);
    }
    final cur = _textController.text.trimRight();
    final next = cur.isEmpty ? '$said\n' : '$cur\n$said\n';
    _textController.text = next;
    _textController.selection = TextSelection.collapsed(offset: next.length);
    setState(() {});
  }

  Future<void> _playTake(_Take take) async {
    if (_isPlaying && _playingPath == take.path) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playingPath = null;
        });
      }
      return;
    }
    await TtsService.stop();
    await _audioPlayer.play(DeviceFileSource(take.path));
    if (mounted) {
      setState(() {
        _isPlaying = true;
        _playingPath = take.path;
      });
    }
  }

  Future<void> _hearAloud() async {
    final words = _textController.text.trim();
    if (words.isEmpty) return;
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _isPlaying = false;
        _playingPath = null;
      });
    }
    await TtsService.speak(words);
  }

  Future<void> _saveCapture() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _takes.isEmpty) {
      _leaveWithoutSaving();
      return;
    }

    final tags = ['quick-thought'];
    if (_memoryLevel == MemoryLevel.remember) tags.add('remember-this');
    if (_memoryLevel == MemoryLevel.memorize) tags.add('memorize-this');
    tags.addAll(
        _selectedTags); // include user chosen tags like crisis, good, felt safe etc.
    if (widget.forDate != null && widget.forDate!.trim().isNotEmpty) {
      tags.add('day-idea');
    }

    // EVERY take is kept, not just the last one: a person who recorded
    // three times said three things, and a voice that was recorded must
    // never be orphaned on disk. The first is the memory's voice; the
    // rest ride along in order.
    final heard = _takes
        .map((t) => t.heard.trim())
        .where((h) => h.isNotEmpty)
        .join('\n');

    final capture = QuickCapture(
      id: _uuid.v4(),
      at: DateTime.now(),
      // A voice-only thought still saves readable words: the transcript
      // stands in as the text when nothing was typed.
      text: text.isNotEmpty ? text : null,
      audioPath: _takes.isEmpty ? null : _takes.first.path,
      extraAudioPaths: _takes.length < 2
          ? const []
          : _takes.skip(1).map((t) => t.path).toList(),
      transcript: heard.isEmpty ? null : heard,
      linkedRoutineId: widget.linkedRoutineId,
      linkedEventId: widget.linkedEventId,
      tags: tags,
      memoryLevel: _memoryLevel,
      contextNote: _contextController.text.trim().isEmpty
          ? null
          : _contextController.text.trim(),
      forDate: widget.forDate,
    );

    try {
      await IsarService.addCapture(capture);
    } catch (_) {
      // Even a broken save must not eat the person's words: everything
      // stays on this screen, said honestly — never a cheerful "saved"
      // over a void (owner QA, 2026-08-14).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(L.t(
                'Could not save just now — your words are still right here. '
                    'Try again in a moment.',
                'לא הצלחתי לשמור כרגע — המילים שלך עדיין כאן. '
                    'אפשר לנסות שוב עוד רגע.'))));
      }
      return;
    }

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
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
      // WHAT WAS KEPT MUST BE SEEN — but the way back matters too.
      // Going straight to /memories replaced the whole stack, and the
      // screens that WAIT for this one (a routine's "didn't happen"
      // wants the words for its skip record) never got their answer —
      // the skip was silently never logged. So: hand the answer back
      // when someone is waiting; Today shows the kept thought in its
      // "What you kept" strip anyway. Only a capture with nowhere to
      // return to (the home-screen 🎤) lands on the list itself.
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
      } else {
        context.go('/memories');
      }
    }
  }

  void _leaveWithoutSaving() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    } else {
      context.go('/');
    }
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Keep this', 'לשמור את זה'),
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
                      'Let it out. Only you can see this. It burns out on its own.',
                      'להוציא הכול. רק אתם רואים את זה. זה נמחק מעצמו.')
                  : L.t(
                      'Speak. We keep your voice and write the words. Hear them read, edit them, add more.',
                      'מדברים. שומרים את הקול וכותבים את המילים. אפשר להקריא, לערוך, ולהוסיף עוד.'),
              style: const TextStyle(fontSize: 18, height: 1.35),
            ),
            const SizedBox(height: 24),

            // ONE mic. Records the voice, then writes the words.
            Center(
              child: GestureDetector(
                onTap: _isRecording || !_hearingWords ? _toggleRecording : null,
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
                                color: Colors.red.withValues(alpha: 0.4),
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
                        'מקליטים… ${_formatDuration(_recordDuration)} — הקשה לעצירה')
                    : _hearingWords
                        ? L.t('Writing the words…', 'כותבים את המילים…')
                        : (_takes.isEmpty
                            ? L.t(
                                'Tap to speak. We write the words.',
                                'הקשה כדי לדבר. נכתוב את המילים.')
                            : L.t(
                                'Tap for another recording — a new line.',
                                'הקשה להקלטה נוספת — שורה חדשה.')),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),

            if (_takes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final take in _takes)
                    FilledButton.tonalIcon(
                      onPressed: () => _playTake(take),
                      icon: Icon(
                        _isPlaying && _playingPath == take.path
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        size: 26,
                      ),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52)),
                      label: Text(recordingLabel(take.number, hebrew: L.isHebrew)),
                    ),
                ],
              ),
            ],

            // Android: the voice is kept, the words still need a door.
            if (_canSpeakWords) ...[
              const SizedBox(height: 16),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        L.t(
                            'Your voice is kept. Words let you find it later '
                                'and let someone read it — say it once more, '
                                'or type it below. Both are fine.',
                            'הקול שלך שמור. מילים עוזרות למצוא את זה אחר כך '
                                'ולתת למישהו לקרוא — אפשר להגיד את זה עוד פעם, '
                                'או להקליד למטה. שתי הדרכים בסדר.'),
                        style: const TextStyle(fontSize: 15, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _speakWordsForLastTake,
                        icon: const Icon(Icons.record_voice_over, size: 26),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56)),
                        label: Text(
                            L.t('Say it in words', 'להגיד את זה במילים')),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: _textController,
              maxLines: 8,
              minLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: L.t(
                    'The words appear here. You can edit them, or write more.',
                    'המילים מופיעות כאן. אפשר לערוך, או לכתוב עוד.'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _hearAloud,
              icon: const Icon(Icons.volume_up_rounded, size: 26),
              label: Text(L.t('Hear the words', 'להקריא את המילים')),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _saveCapture,
              icon: const Icon(Icons.check, size: 28),
              label: Text(L.t('Save — I will see it', 'שמירה — אני אראה את זה')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _leaveWithoutSaving,
              child: Text(L.t('Not now', 'לא עכשיו')),
            ),

            // Extra choices stay closed. Asking "how important?" on the
            // main path made people lose the thought — and hid it after.
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _showMore = !_showMore),
              child: Text(_showMore
                  ? L.t('Less', 'פחות')
                  : L.t('A little more', 'עוד קצת')),
            ),
            if (_showMore) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L.t('Keep this one always', 'לשמור את זה תמיד')),
                value: _memoryLevel == MemoryLevel.memorize,
                onChanged: (v) => setState(() {
                  _memoryLevel = v ? MemoryLevel.memorize : defaultKeptLevel;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(L.t('Family can know this one',
                    'המשפחה יכולה לדעת על זה')),
                value: _selectedTags.contains('family'),
                onChanged: (v) => setState(() {
                  if (v) {
                    _selectedTags.add('family');
                  } else {
                    _selectedTags.remove('family');
                  }
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _contextController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: L.t('A little more about it', 'עוד קצת על זה'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Take {
  final int number;
  final String path;

  /// What the device ear heard in THIS take — kept apart from the text box
  /// so the person's own edits stay theirs and the machine's words stay
  /// the machine's (the transcript is what travels in the .bns).
  final String heard;

  const _Take(this.number, this.path, this.heard);
}
