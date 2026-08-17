import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/tag_flair.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';

/// THE HAND THAT PUTS A MARK ON A MOMENT (owner, 2026-08-16: the tag
/// system existed only as plumbing — no version had a way to choose one).
///
/// One quiet wrap of word-chips: the known marks, gentlest first, plus
/// every word the person invented, plus a door for a new word of their
/// own. Used on capture (before the save) and on a kept memory (after —
/// a mark is allowed to arrive later than the moment).
///
/// Laws honored here:
///   * A button wears its name — chips are words with icons, 48dp targets.
///   * Marks with their own doors (family, the flame, the skip sheet)
///     never appear as chips; see [kPickerReservedTags].
///   * No motion: selection is a color that simply is, or isn't.
class MarkPicker extends StatefulWidget {
  /// The live tag set being edited. The picker adds and removes here.
  final Set<String> selected;
  final VoidCallback onChanged;

  /// The person's own past words (see [ownMarksOf]) — a word invented
  /// yesterday is one tap today, never retyped (fluency, 2026-08-17).
  final List<String> vocabulary;

  const MarkPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.vocabulary = const [],
  });

  @override
  State<MarkPicker> createState() => _MarkPickerState();
}

class _MarkPickerState extends State<MarkPicker> {
  bool _addingWord = false;
  final _wordCtrl = TextEditingController();

  @override
  void dispose() {
    _wordCtrl.dispose();
    super.dispose();
  }

  bool _isOn(String canonicalKey) =>
      widget.selected.any((t) => canonicalTag(t) == canonicalKey);

  void _toggle(String key) {
    setState(() {
      if (_isOn(key)) {
        widget.selected.removeWhere((t) => canonicalTag(t) == key);
      } else {
        widget.selected.add(key);
      }
    });
    widget.onChanged();
  }

  /// The person's whole reachable vocabulary: words on THIS moment plus
  /// the words they invented before ([MarkPicker.vocabulary]) — each one
  /// a single tap, in one deduped freshest-first row.
  List<String> get _ownWords {
    final out = <String>[];
    final seen = <String>{};
    void keep(String t) {
      final c = canonicalTag(t);
      if (c.isEmpty || kPlumbingTags.contains(c)) return;
      if (kPickerReservedTags.contains(c)) return;
      if (kChoosableMarks.contains(c)) return;
      if (seen.add(c)) out.add(t);
    }

    widget.selected.forEach(keep);
    widget.vocabulary.forEach(keep);
    return out;
  }

  void _addOwnWord(String raw) {
    final word = raw.replaceAll('#', '').trim();
    _wordCtrl.clear();
    if (word.isEmpty) {
      setState(() => _addingWord = false);
      return;
    }
    final c = canonicalTag(word);
    // The app's filing words, the storm, and the marks with their own
    // doors are not a person's mark — typing "family" must not silently
    // trip the export path.
    if (kPlumbingTags.contains(c) || kPickerReservedTags.contains(c)) {
      setState(() => _addingWord = false);
      return;
    }
    setState(() {
      widget.selected.add(word);
      _addingWord = false;
    });
    widget.onChanged();
  }

  Widget _chip(BuildContext context, String keyOrWord) {
    final cs = Theme.of(context).colorScheme;
    final look = tagLook(keyOrWord)!;
    final key = canonicalTag(keyOrWord);
    final on = _isOn(key);
    final tint = look.color(cs);
    return FilterChip(
      avatar: Icon(look.icon, size: 18, color: on ? tint : cs.onSurfaceVariant),
      label: Text(look.label),
      selected: on,
      showCheckmark: false,
      selectedColor: tint.withValues(alpha: 0.16),
      side: BorderSide(
          color: on ? tint.withValues(alpha: 0.45) : cs.outlineVariant),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
        color: on ? tint : cs.onSurfaceVariant,
      ),
      onSelected: (_) => _toggle(key),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final key in kChoosableMarks) _chip(context, key),
        for (final word in _ownWords) _chip(context, word),
        if (_addingWord)
          SizedBox(
            width: 240,
            child: TextField(
              controller: _wordCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                hintText: L.t('Your word', 'המילה שלכם'),
                border: const OutlineInputBorder(),
                // Voice-first everywhere: a person who cannot type can
                // still invent a mark (fluency gap #3, 2026-08-17).
                suffixIcon: DictationMicButton(controller: _wordCtrl),
              ),
              // Only a deliberate submit makes a mark — a stray tap used
              // to turn a half-typed word into a permanent one.
              onSubmitted: _addOwnWord,
            ),
          )
        else
          ActionChip(
            avatar: Icon(Icons.add, size: 18, color: cs.onSurfaceVariant),
            label: Text(L.t('A word of your own', 'מילה משלכם')),
            labelStyle: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            onPressed: () => setState(() => _addingWord = true),
          ),
      ],
    );
  }
}
