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
import 'package:bns/core/tag_flair.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/platform/android_widget.dart';
import 'package:bns/services/apple_file_stt.dart';
import 'package:bns/services/speech_popup.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/services/vosk_service.dart';
import 'package:bns/services/whisper_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';
import 'package:bns/ui/widgets/mark_picker.dart';

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

  /// A FRESH VISIT, ASKED FOR OUT LOUD (level-1 note, 2026-08-17: "cold
  /// open kept old text"). go_router reuses this screen's State when
  /// /capture is asked for while already showing (same page key), so a
  /// widget-button or door arrival landed in last visit's leftovers —
  /// and a new autoRecord was silently skipped. Callers that `go` here
  /// call [askFresh] first; the open screen BANKS any unsaved words
  /// (words are never lost — they land as a kept thought) and starts
  /// the visit clean with the new extras.
  static final ValueNotifier<int> freshVisit = ValueNotifier<int>(0);
  static Map<String, dynamic>? _freshExtra;

  static void askFresh([Map<String, dynamic>? extra]) {
    _freshExtra = extra;
    freshVisit.value++;
  }

  /// The pending fresh-visit extras, consumed exactly once.
  static Map<String, dynamic>? takeFreshExtra() {
    final e = _freshExtra;
    _freshExtra = null;
    return e;
  }

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
  // Anchor for scrolling the opened options into view (guided bar case).
  final GlobalKey _moreOptionsKey = GlobalKey();
  final _contextController =
      TextEditingController(); // for "what happened / why" in remember/memorize
  final Set<String> _selectedTags =
      {}; // for crisis, good, garden tags, search by routine/crisis

  /// One save at a time — a double-tap must not keep the thought twice.
  bool _saving = false;

  /// The person's own past mark words, freshest first — one tap today.
  List<String> _markVocabulary = const [];

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
    QuickCaptureScreen.takeFreshExtra(); // this visit IS fresh; drop leftovers
    QuickCaptureScreen.freshVisit.addListener(_onFreshVisitAsked);
    // Marks suggest themselves from the words as they land.
    _textController.addListener(_refreshSuggestions);
    _loadMarkVocabulary();
  }

  Future<void> _loadMarkVocabulary() async {
    final all = await IsarService.getAllCaptures();
    if (!mounted) return;
    setState(() => _markVocabulary = ownMarksOf(visibleMemories(all)));
  }

  void _refreshSuggestions() {
    if (mounted) setState(() {});
  }

  /// A new arrival while this screen is already open: bank unsaved words
  /// (never lost — they land as a kept thought), then start clean.
  Future<void> _onFreshVisitAsked() async {
    if (!mounted) return;
    final extra = QuickCaptureScreen.takeFreshExtra() ?? const {};
    if (_textController.text.trim().isNotEmpty || _takes.isNotEmpty) {
      final banked = await _keepQuietly();
      if (!banked) return; // words stay put rather than risk losing them
    }
    if (!mounted) return;
    setState(() {
      _textController.clear();
      _contextController.clear();
      _takes.clear();
      _selectedTags.clear();
      _memoryLevel = defaultKeptLevel;
      _showMore = false;
      final tags = extra['tags'];
      if (tags is List) _selectedTags.addAll(tags.cast<String>());
    });
    if (extra['autoRecord'] == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoStart());
    }
  }

  /// Bank the current words/voice as a kept thought without leaving or
  /// announcing — the fresh visit's quiet guard. True on success.
  Future<bool> _keepQuietly() async {
    try {
      await IsarService.addCapture(_assembleCapture());
      return true;
    } catch (_) {
      return false;
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
    QuickCaptureScreen.freshVisit.removeListener(_onFreshVisitAsked);
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

  /// Voice is already safe. Then the words — and ONLY real words: a take
  /// the engines couldn't read writes NOTHING into the box (owner beta
  /// report, 2026-08-15: an empty "הקלטה 1" header standing where his
  /// words should be — "not close to my vision"). On Android, where no
  /// engine can read the file, the system speech sheet opens BY ITSELF
  /// right after the voice is kept: talk → sheet → words. One flow, not
  /// a card asking to press again.
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
    if (heard.trim().isNotEmpty) {
      final next = appendSpokenWords(
        current: _textController.text,
        words: heard,
      );
      _textController.text = next;
      _textController.selection =
          TextSelection.collapsed(offset: next.length);
    }
    setState(() => _hearingWords = false);
    // NOTHING SPEAKS OR LISTENS UNINVITED (owner as user, 2026-08-19:
    // "the recording button is making a recording and then it starts
    // the TTS which is not what I aimed at"). The take is kept, the
    // room stays quiet. The worded voice-typing door below opens the
    // system ear only when pressed.
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
    // The take that ASKED is the take that gets the words — a recording
    // started while the popup was open must not steal them.
    final asking = _takes.isEmpty ? null : _takes.last;
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
    final i = asking == null
        ? -1
        : _takes.indexWhere((t) => t.path == asking.path);
    if (i >= 0) {
      _takes[i] = _Take(_takes[i].number, _takes[i].path, said);
    }
    final next = appendSpokenWords(current: _textController.text, words: said);
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

  /// One assembly for every keep — the visible Save and the quiet bank
  /// build the identical memory.
  QuickCapture _assembleCapture() {
    final text = _textController.text.trim();

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

    return QuickCapture(
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
  }

  Future<void> _saveCapture() async {
    if (_saving) return; // a double-tap must not keep the thought twice
    final text = _textController.text.trim();
    if (text.isEmpty && _takes.isEmpty) {
      _leaveWithoutSaving();
      return;
    }
    _saving = true;

    try {
      await IsarService.addCapture(_assembleCapture());
    } catch (_) {
      _saving = false;
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
              ? L.t('Kept permanently.', 'נשמר לתמיד.')
              : L.t('Saved.', 'נשמר.');
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
        // Home, where the "What you kept" strip shows the new thought —
        // /memories from a root capture stranded people off-map (level-1
        // tester: Save should end where the day is, with proof in view).
        context.go('/');
      }
    }
    _saving = false;
  }

  /// No path out of this screen may silently cost words (level-1 tester,
  /// 2026-08-16: typed `sunday_tinker`, pressed Save, landed elsewhere,
  /// note gone). A box with words in it asks before it lets go — whatever
  /// weird route brought the exit.
  Future<void> _leaveWithoutSaving() async {
    final hasWords =
        _textController.text.trim().isNotEmpty || _takes.isNotEmpty;
    if (hasWords) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(L.t('Leave without keeping?', 'לצאת בלי לשמור?')),
          content: Text(L.t(
              'There are words (or a voice) here that were not saved yet.',
              'יש כאן מילים (או קול) שעוד לא נשמרו.')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(L.t('Stay', 'להישאר'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(L.t('Leave', 'לצאת'))),
          ],
        ),
      );
      if (sure != true || !mounted) return;
    }
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
      // ONE SAVE, ALWAYS IN REACH (level-1 note, 2026-08-17: "two saves...
      // the keyboard covers the big save"). The header שמירה is gone —
      // the one Save door is PINNED under the screen and rides above the
      // keyboard; two identical doors made every save a coin-flip story.
      appBar: BnsAppBar(title: L.t('Keep this', 'לשמור את זה')),
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

            // The words sheet already opened by itself after the take; this
            // small door is only the second chance when it was declined.
            // A quiet button, not a lecture.
            if (_canSpeakWords) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _speakWordsForLastTake,
                icon: const Icon(Icons.record_voice_over, size: 24),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                label: Text(L.t('Add words to this voice',
                    'להוסיף מילים לקול הזה')),
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
                // Dictation straight into the box — STT everywhere law.
                suffixIcon: DictationMicButton(controller: _textController),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _hearAloud,
              icon: const Icon(Icons.volume_up_rounded, size: 26),
              label: Text(L.t('Hear the words', 'להקריא את המילים')),
            ),

            // Extra choices stay closed — but behind a door that SAYS
            // what is inside ("עוד קצת" said nothing; owner beta report,
            // 2026-08-15). A word-labeled door, same as everywhere else.
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() => _showMore = !_showMore);
                // The guided "back to my day" bar shortens the viewport;
                // an opened door whose switches hide below the fold is a
                // wall for a level-4 hand (tester, 2026-08-16: "the bar
                // covers it until you scroll"). Bring them into view.
                if (_showMore) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final ctx = _moreOptionsKey.currentContext;
                    if (ctx != null) {
                      Scrollable.ensureVisible(ctx,
                          alignment: 0.5,
                          duration: Duration.zero); // static app — no glide
                    }
                  });
                }
              },
              icon: Icon(_showMore ? Icons.expand_less : Icons.expand_more,
                  size: 22),
              label: Text(
                  _showMore
                      ? L.t('Close the options', 'לסגור את האפשרויות')
                      : _selectedTags.contains('mad-vent')
                          ? L.t('Keep forever · context',
                              'לשמור לתמיד · הקשר')
                          : L.t('Keep forever · family · a mark · context',
                              'לשמור לתמיד · משפחה · סימן · הקשר'),
                  style: const TextStyle(fontSize: 15)),
            ),
            if (_showMore) ...[
              SwitchListTile(
                key: _moreOptionsKey,
                contentPadding: EdgeInsets.zero,
                title: Text(L.t('Keep this one always', 'לשמור את זה תמיד')),
                value: _memoryLevel == MemoryLevel.memorize,
                onChanged: (v) => setState(() {
                  _memoryLevel = v ? MemoryLevel.memorize : defaultKeptLevel;
                }),
              ),
              // A storm is a storm: while venting there is no family
              // switch (the share it promised was a lie — filtered
              // exports strip mad-vents by law) and no marks to weigh.
              if (!_selectedTags.contains('mad-vent')) ...[
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
                const SizedBox(height: 12),
                Text(
                  L.t('A mark on this moment', 'סימן על הרגע'),
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                MarkPicker(
                  selected: _selectedTags,
                  vocabulary: _markVocabulary,
                  onChanged: () => setState(() {}),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _contextController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: L.t('What was around it? (context)',
                      'מה היה מסביב? (הקשר)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
      // THE ONE SAVE, PINNED — it rides above the keyboard (the body's
      // Save drowned under it; level-1 note, 2026-08-17), with the marks
      // that offered themselves from the person's own words just above:
      // one tap accepts a mark, nothing applies itself.
      bottomNavigationBar: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_selectedTags.contains('mad-vent'))
                _SuggestedMarksRow(
                  words: _textController.text,
                  vocabulary: _markVocabulary,
                  alreadyChosen: _selectedTags,
                  onAccept: (mark) =>
                      setState(() => _selectedTags.add(mark)),
                ),
              FilledButton.icon(
                onPressed: _saveCapture,
                icon: const Icon(Icons.check, size: 28),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                // The void-promise without a navigation promise (tester,
                // 2026-08-16: "Save promises 'אני אראה את זה' but lands
                // on Today"). Saving stays in place; the kept strip shows it.
                label: Text(
                    L.t('Save — it stays with me', 'שמירה — זה נשאר אצלי')),
              ),
              TextButton(
                onPressed: _leaveWithoutSaving,
                style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44)),
                child: Text(L.t('Not now', 'לא עכשיו')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The marks living inside the words, offered as one quiet chip row.
/// Renders nothing when the words hold no known mark — no empty chrome.
class _SuggestedMarksRow extends StatelessWidget {
  final String words;
  final List<String> vocabulary;
  final Set<String> alreadyChosen;
  final ValueChanged<String> onAccept;

  const _SuggestedMarksRow({
    required this.words,
    required this.vocabulary,
    required this.alreadyChosen,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final offers = suggestMarksFor(words,
        vocabulary: vocabulary, alreadyChosen: alreadyChosen);
    if (offers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final mark in offers)
            Builder(builder: (context) {
              final look = tagLook(mark)!;
              final tint = look.color(cs);
              return ActionChip(
                avatar: Icon(look.icon, size: 18, color: tint),
                label: Text(L.t('Mark: ${look.label}', 'סימן: ${look.label}')),
                labelStyle: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: tint),
                side: BorderSide(color: tint.withValues(alpha: 0.45)),
                onPressed: () => onAccept(mark),
              );
            }),
        ],
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
