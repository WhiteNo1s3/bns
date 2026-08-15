/// HOW A TAG LOOKS (owner, 2026-08-15: "we can add flare for tags maybe").
///
/// Tags were write-only: a moment could be marked `crisis` or `family` and
/// then look exactly like every other line forever. A tag nobody can see
/// is a tag nobody trusts — and "show me the hard ones" was impossible
/// without reading every memory again.
///
/// Two rules keep this from becoming clutter:
///   1. PLUMBING NEVER SHOWS. `quick-thought`, `remember-this` and friends
///      are how the app files things, not something a person chose to say.
///   2. The word shown is the person's word, in their language — never the
///      internal key (`felt out of bound` is not a label for a human).
///
/// Colors are roles from the theme, so every palette and dark mode follow
/// along; nothing here hardcodes a brand color.
library;

import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';

/// Tags the app writes for its own filing. Never shown as flair.
const Set<String> kPlumbingTags = {
  'quick-thought',
  'remember-this',
  'memorize-this',
  'auto-summary',
  'day-memory',
  'goal-progress',
  'diary',
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
  final t = tag.trim().toLowerCase();
  if (t.isEmpty || kPlumbingTags.contains(t)) return null;

  switch (t) {
    case 'crisis':
      return TagLook(
        label: L.t('crisis', 'משבר'),
        icon: Icons.priority_high_rounded,
        color: (cs) => cs.error,
      );
    case 'need-help':
      return TagLook(
        label: L.t('got in the way', 'משהו הפריע'),
        icon: Icons.pan_tool_outlined,
        color: (cs) => cs.tertiary,
      );
    case 'good':
      return TagLook(
        label: L.t('good', 'טוב'),
        icon: Icons.wb_sunny_outlined,
        color: (cs) => cs.primary,
      );
    case 'felt safe':
      return TagLook(
        label: L.t('felt safe', 'הרגשתי בטוח'),
        icon: Icons.shield_outlined,
        color: (cs) => cs.primary,
      );
    case 'felt confused':
      return TagLook(
        label: L.t('felt confused', 'הרגשתי מבולבל'),
        icon: Icons.help_outline,
        color: (cs) => cs.tertiary,
      );
    case 'felt out of bound':
      return TagLook(
        label: L.t('felt too much', 'הרגשתי יותר מדי'),
        icon: Icons.waves_outlined,
        color: (cs) => cs.tertiary,
      );
    case 'drama':
      return TagLook(
        label: L.t('drama', 'דרמה'),
        icon: Icons.theater_comedy_outlined,
        color: (cs) => cs.secondary,
      );
    case 'wonderings':
      return TagLook(
        label: L.t('wondering', 'תהיות'),
        icon: Icons.lightbulb_outline,
        color: (cs) => cs.secondary,
      );
    case 'family':
      return TagLook(
        label: L.t('family can know', 'המשפחה יודעת'),
        icon: Icons.family_restroom,
        color: (cs) => cs.primary,
      );
    case 'routine':
      return TagLook(
        label: L.t('routine', 'שגרה'),
        icon: Icons.repeat_rounded,
        color: (cs) => cs.onSurfaceVariant,
      );
    case 'mad-vent':
      return TagLook(
        label: L.t('storm', 'סערה'),
        icon: Icons.whatshot_outlined,
        color: (cs) => cs.error,
      );
    default:
      // A tag the person invented is still theirs to see.
      return TagLook(
        label: tag.trim(),
        icon: Icons.label_outline,
        color: (cs) => cs.onSurfaceVariant,
      );
  }
}

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
