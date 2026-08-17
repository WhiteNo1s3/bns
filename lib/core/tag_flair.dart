/// HOW A TAG LOOKS — and now, how it is CHOSEN and FOUND
/// (owner, 2026-08-15: "we can add flare for tags maybe";
/// owner, 2026-08-16: "improve to maximum the tagging system which
/// doesn't exist in practice in any of the versions").
///
/// Tags were write-only twice over: a moment could carry `crisis` or
/// `family` and then look like every other line forever — and there was
/// no hand to PUT a mark on a moment in the first place, and no door to
/// ask "show me the hard ones". The model was there; the system wasn't.
/// This file is the one law for what a mark is: its words, its look,
/// which marks a person can choose, and how a search finds them.
///
/// Rules that keep this from becoming clutter:
///   1. PLUMBING NEVER SHOWS. `quick-thought`, `remember-this` and
///      friends are how the app files things, not something a person
///      chose to say.
///   2. The word shown is the person's word, in their language — never
///      the internal key (`felt out of bound` is not a label for a
///      human, and neither is `asked-help`).
///   3. A mark the person invented is still theirs to see — their word,
///      as they typed it.
///   4. Search speaks the person's language: typing «משבר» finds a
///      moment stored as `crisis`, because the stored key is plumbing
///      and the label is the truth.
///
/// Colors are roles from the theme, so every palette and dark mode follow
/// along; nothing here hardcodes a brand color.
library;

import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/quick_capture.dart';

/// Tags the app writes for its own filing. Never shown as flair.
const Set<String> kPlumbingTags = {
  'quick-thought',
  'remember-this',
  'memorize-this',
  'auto-summary',
  'day-memory',
  'goal-progress',
  'diary',
  'day-idea',
};

/// One spelling for comparing tags: no '#', no case, no stray spaces.
/// Storage keeps the person's own spelling; comparison uses this.
String canonicalTag(String tag) =>
    tag.replaceAll('#', '').trim().toLowerCase();

Color _cError(ColorScheme cs) => cs.error;
Color _cPrimary(ColorScheme cs) => cs.primary;
Color _cSecondary(ColorScheme cs) => cs.secondary;
Color _cTertiary(ColorScheme cs) => cs.tertiary;
Color _cQuiet(ColorScheme cs) => cs.onSurfaceVariant;

class _TagSpec {
  final String en;
  final String he;
  final IconData icon;
  final Color Function(ColorScheme) color;

  const _TagSpec(this.en, this.he, this.icon, this.color);
}

/// Every mark the app knows by name — both languages live here so search
/// can match the words a person actually reads, whatever the UI language.
const Map<String, _TagSpec> _kKnownTags = {
  'crisis': _TagSpec('crisis', 'משבר', Icons.priority_high_rounded, _cError),
  'need-help':
      _TagSpec('got in the way', 'משהו הפריע', Icons.pan_tool_outlined, _cTertiary),
  'asked-help': _TagSpec(
      'asked for help', 'ביקשתי עזרה', Icons.record_voice_over_outlined, _cTertiary),
  'good': _TagSpec('good', 'טוב', Icons.wb_sunny_outlined, _cPrimary),
  'felt safe':
      _TagSpec('felt safe', 'הרגשתי בטוח', Icons.shield_outlined, _cPrimary),
  'felt confused':
      _TagSpec('felt confused', 'הרגשתי מבולבל', Icons.help_outline, _cTertiary),
  'felt out of bound':
      _TagSpec('felt too much', 'הרגשתי יותר מדי', Icons.waves_outlined, _cTertiary),
  'drama': _TagSpec('drama', 'דרמה', Icons.theater_comedy_outlined, _cSecondary),
  'wonderings':
      _TagSpec('wondering', 'תהיות', Icons.lightbulb_outline, _cSecondary),
  'family':
      _TagSpec('family can know', 'המשפחה יודעת', Icons.family_restroom, _cPrimary),
  'routine': _TagSpec('routine', 'שגרה', Icons.repeat_rounded, _cQuiet),
  'mad-vent': _TagSpec('storm', 'סערה', Icons.whatshot_outlined, _cError),
};

/// The marks a person can put on a moment with one tap, gentlest first —
/// the good words lead, the hard word is available, nothing is pushed.
const List<String> kChoosableMarks = [
  'good',
  'felt safe',
  'wonderings',
  'drama',
  'felt confused',
  'felt out of bound',
  'crisis',
];

/// Marks that have their own doors and flows (the family switch, the
/// flame, the skip sheet). The picker never offers them as chips.
const Set<String> kPickerReservedTags = {
  'family',
  'mad-vent',
  'need-help',
  'asked-help',
  'routine',
};

/// How one tag should look on screen.
class TagLook {
  final String label;
  final IconData icon;

  /// Picks its color from the theme's roles, never a fixed hex.
  final Color Function(ColorScheme) color;

  const TagLook({
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// The look for [tag], or null when it is plumbing and should stay hidden.
TagLook? tagLook(String tag) {
  final t = canonicalTag(tag);
  if (t.isEmpty || kPlumbingTags.contains(t)) return null;

  final spec = _kKnownTags[t];
  if (spec != null) {
    return TagLook(
      label: L.t(spec.en, spec.he),
      icon: spec.icon,
      color: spec.color,
    );
  }
  // A mark the person invented is still theirs to see.
  return TagLook(
    label: tag.replaceAll('#', '').trim(),
    icon: Icons.label_outline,
    color: _cQuiet,
  );
}

/// True when [tag] answers [query] — by its stored spelling or by the
/// words the person reads for it, in either language. «משבר» finds
/// `crisis`; "storm" finds `mad-vent`; a person's own word finds itself.
bool tagMatchesQuery(String tag, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final c = canonicalTag(tag);
  if (c.contains(q)) return true;
  final spec = _kKnownTags[c];
  if (spec == null) return false;
  return spec.en.toLowerCase().contains(q) || spec.he.contains(q);
}

/// True when this kept moment answers [query]: its words, or any of its
/// marks by label. One matcher for every list that searches memories.
bool memoryMatchesQuery(QuickCapture c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (memoryWords(c).toLowerCase().contains(q)) return true;
  return c.tags.any((t) => tagMatchesQuery(t, q));
}

/// The marks worth offering as filters for [items]: every distinct
/// visible mark, first-seen order (give it the newest-first list and the
/// freshest marks lead). Canonical keys out; feed them to [tagLook].
List<String> flairTagsOf(Iterable<QuickCapture> items) {
  final seen = <String>{};
  final out = <String>[];
  for (final c in items) {
    for (final t in c.tags) {
      final key = canonicalTag(t);
      if (key.isEmpty || kPlumbingTags.contains(key)) continue;
      if (tagLook(t) == null) continue;
      if (seen.add(key)) out.add(key);
    }
  }
  return out;
}

/// True when the moment carries [canonicalKey] under any spelling.
bool memoryHasTag(QuickCapture c, String canonicalKey) =>
    c.tags.any((t) => canonicalTag(t) == canonicalKey);

/// A mark the app knows by name, as opposed to a person's own word.
bool isKnownMark(String tag) => _kKnownTags.containsKey(canonicalTag(tag));

/// THE PERSON'S OWN MARK VOCABULARY, freshest first (feed a newest-first
/// list). A word invented yesterday belongs on today's picker — it used
/// to live only on the moment it was typed on, so it could never be
/// used twice without retyping it exactly (fluency gap #1, 2026-08-17).
List<String> ownMarksOf(Iterable<QuickCapture> items) => flairTagsOf(items)
    .where((k) =>
        !_kKnownTags.containsKey(k) && !kPickerReservedTags.contains(k))
    .toList();

/// MARKS THAT OFFER THEMSELVES (owner, 2026-08-17: tagging "gotta be
/// fluent"). Read the person's words and surface the marks already
/// living inside them: their own past words by containment (Hebrew
/// prefixes come free), the built-in choosables by their labels in
/// either language (English on word boundaries — "good" must not hide
/// inside "goodbye"). One tap accepts; nothing is ever applied by
/// itself, and the reserved doors (family, storm…) never volunteer.
List<String> suggestMarksFor(
  String words, {
  List<String> vocabulary = const [],
  Iterable<String> alreadyChosen = const [],
  int max = 3,
}) {
  final text = words.trim().toLowerCase();
  if (text.isEmpty) return const [];
  final chosen = alreadyChosen.map(canonicalTag).toSet();
  final out = <String>[];

  void offer(String key) {
    final k = canonicalTag(key);
    if (k.isEmpty || chosen.contains(k) || out.contains(k)) return;
    if (kPickerReservedTags.contains(k) || kPlumbingTags.contains(k)) return;
    out.add(k);
  }

  // The person's own words lead — they are the person's language.
  for (final own in vocabulary) {
    final w = canonicalTag(own);
    if (w.length >= 2 && text.contains(w)) offer(own);
  }
  for (final key in kChoosableMarks) {
    final spec = _kKnownTags[key]!;
    final enHit = RegExp('\\b${RegExp.escape(spec.en.toLowerCase())}\\b')
        .hasMatch(text);
    if (enHit || text.contains(spec.he)) offer(key);
  }
  return out.length <= max ? out : out.sublist(0, max);
}

/// True when at least one of [tags] would show as flair.
bool tagsHaveFlair(Iterable<String> tags) =>
    tags.any((t) => tagLook(t) != null);

/// A quiet row of tag chips. Renders nothing when there is nothing to say.
class TagFlairRow extends StatelessWidget {
  final List<String> tags;
  final double scale;

  const TagFlairRow({super.key, required this.tags, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final looks = <TagLook>[];
    final seen = <String>{};
    for (final t in tags) {
      final look = tagLook(t);
      if (look == null) continue;
      if (!seen.add(look.label)) continue; // never the same word twice
      looks.add(look);
    }
    if (looks.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final look in looks)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              // Tinted, not shouting: a mark on the moment, not a warning.
              color: look.color(cs).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: look.color(cs).withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(look.icon, size: 16 * scale, color: look.color(cs)),
                const SizedBox(width: 6),
                Text(
                  look.label,
                  style: TextStyle(
                    fontSize: 13 * scale,
                    fontWeight: FontWeight.w600,
                    color: look.color(cs),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
