import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/recording_text.dart';
import 'package:bns/core/tag_flair.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/ui/widgets/mark_picker.dart';

/// One memory, still and clear. The person sees the words they kept,
/// hears the voice if there is one, and can leave without a quiz.
///
/// A mark is allowed to arrive later than the moment: the marks editor
/// lives here, so "that was actually a crisis" or "family can know
/// after all" is a decision the person can make any day — always their
/// side of the wall. Storms are the exception: a vent is not edited,
/// not re-marked, never family-switched (it burns out on its own).
class MemoryViewScreen extends StatefulWidget {
  final QuickCapture memory;

  const MemoryViewScreen({super.key, required this.memory});

  @override
  State<MemoryViewScreen> createState() => _MemoryViewScreenState();
}

class _MemoryViewScreenState extends State<MemoryViewScreen> {
  late QuickCapture _memory = widget.memory;
  late final Set<String> _tags = {...widget.memory.tags};
  bool _editingMarks = false;

  bool get _isVent => _tags.any((t) => canonicalTag(t) == 'mad-vent');

  Future<void> _play(String path) async {
    try {
      await AudioPlaybackService.toggle(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'The sound for this one is not on this device anymore.',
              'הצליל של הזיכרון הזה כבר לא נמצא במכשיר הזה.'))));
    }
  }

  /// Every mark change lands immediately — no second Save to forget.
  Future<void> _persistTags() async {
    _memory = await IsarService.addCapture(
      _memory.copyWith(tags: _tags.toList()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _keepForever() async {
    _memory = await IsarService.addCapture(
      _memory.copyWith(memoryLevel: MemoryLevel.memorize),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(L.t('This one will stay.', 'זה יישאר.')),
      duration: const Duration(seconds: 2),
    ));
    Navigator.pop(context, true);
  }

  Future<void> _trash() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t('Put this away?', 'להניח את זה בצד?')),
        content: Text(L.t(
            'It waits in trash for 3 days. You can bring it back.',
            'זה מחכה באשפה 3 ימים. אפשר להחזיר.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L.t('Keep it', 'להשאיר'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(L.t('Put away', 'להניח בצד')),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await IsarService.softDeleteCapture(_memory.id);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final words = memoryWords(_memory);
    final dateStr = DateFormat.yMMMMEEEEd(L.isHebrew ? 'he' : 'en')
        .add_Hm()
        .format(_memory.at);
    final forever = _memory.memoryLevel == MemoryLevel.memorize;
    final cs = Theme.of(context).colorScheme;
    final tagList = _tags.toList();

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Kept', 'נשמר'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
          children: [
            Text(
              dateStr,
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
            // What this moment was marked as — visible at last. A tag the
            // person chose used to vanish the moment it was saved.
            if (tagsHaveFlair(tagList)) ...[
              const SizedBox(height: 12),
              TagFlairRow(tags: tagList),
            ],
            if (!_isVent) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _editingMarks = !_editingMarks),
                  icon: Icon(
                      _editingMarks ? Icons.expand_less : Icons.sell_outlined,
                      size: 20),
                  label: Text(_editingMarks
                      ? L.t('Close the marks', 'לסגור את הסימנים')
                      : L.t('Change the marks', 'לשנות את הסימנים')),
                ),
              ),
              if (_editingMarks) ...[
                MarkPicker(selected: _tags, onChanged: _persistTags),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(L.t('Family can know this one',
                      'המשפחה יכולה לדעת על זה')),
                  value: _tags.any((t) => canonicalTag(t) == 'family'),
                  onChanged: (v) {
                    if (v) {
                      _tags.add('family');
                    } else {
                      _tags.removeWhere(
                          (t) => canonicalTag(t) == 'family');
                    }
                    _persistTags();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 8),
            Text(
              words.isEmpty
                  ? L.t('A voice moment — tap play to hear it.',
                      'רגע קולי — הקשה על ניגון כדי לשמוע.')
                  : words,
              style: const TextStyle(fontSize: 22, height: 1.35),
            ),
            if (_memory.contextNote != null &&
                _memory.contextNote!.trim().isNotEmpty &&
                _memory.contextNote!.trim() != words) ...[
              const SizedBox(height: 16),
              Text(
                _memory.contextNote!.trim(),
                style: TextStyle(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),
            if (words.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () => TtsService.speak(words),
                icon: const Icon(Icons.volume_up, size: 28),
                label: Text(L.t('Read it to me', 'להקריא לי')),
              ),
            // Every voice of this moment gets its own button — a second
            // recording is not a lesser one, and none of them hides.
            for (final (i, path) in _memory.allAudioPaths.indexed) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _play(path),
                icon: const Icon(Icons.play_arrow_rounded, size: 32),
                label: Text(_memory.allAudioPaths.length == 1
                    ? L.t('Play my voice', 'לנגן את הקול שלי')
                    : recordingLabel(i + 1, hebrew: L.isHebrew)),
              ),
            ],
            const SizedBox(height: 32),
            if (!forever)
              TextButton.icon(
                onPressed: _keepForever,
                icon: const Icon(Icons.star_outline),
                label: Text(L.t('Keep this one always', 'לשמור את זה תמיד')),
              ),
            if (forever)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  L.t('This one stays.', 'זה נשאר.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.primary),
                ),
              ),
            TextButton(
              onPressed: _trash,
              child: Text(L.t('Put away', 'להניח בצד')),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(L.t('Close', 'סגירה')),
            ),
          ],
        ),
      ),
    );
  }
}
