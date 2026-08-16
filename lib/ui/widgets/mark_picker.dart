import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/tag_flair.dart';

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

  const MarkPicker({
    super.key,
    required this.selected,
    required this.onChanged,
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

  /// The person's own words living in the set right now — everything
  /// that is not a known chip, not reserved, not plumbing.
  List<String> get _ownWords => widget.selected.where((t) {
        final c = canonicalTag(t);
        if (c.isEmpty || kPlumbingTags.contains(c)) return false;
        if (kPickerReservedTags.contains(c)) return false;
        return !kChoosableMarks.contains(c);
      }).toList();

  void _addOwnWord(String raw) {
    final word = raw.replaceAll('#', '').trim();
    _wordCtrl.clear();
    if (word.isEmpty) {
      setState(() => _addingWord = false);
      return;
    }
    final c = canonicalTag(word);
    // The app's filing words and the storm are not a person's mark.
    if (kPlumbingTags.contains(c) || c == 'mad-vent') {
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
            width: 200,
            child: TextField(
              controller: _wordCtrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                hintText: L.t('Your word', 'המילה שלכם'),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _addOwnWord,
              onTapOutside: (_) => _addOwnWord(_wordCtrl.text),
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
