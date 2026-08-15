import 'package:flutter/material.dart';
import 'package:bns/core/models/settings.dart';

/// Screens appear in place — nothing slides, nothing flies (owner law,
/// 2026-07-06: "the app must be static to not make nausea on people").
/// Vestibular sensitivity is common after TBI; moving content is a trigger.
/// Stationary feedback (color changes, ripples) stays — it's the MOTION of
/// content across the screen that's banned.
class _StaticTransitionsBuilder extends PageTransitionsBuilder {
  const _StaticTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // the new screen is simply there — calm, instant, still
  }
}

/// Adapts PillMemorizer color language + relaxing palettes for BNS.
/// Primary source of truth: follow system (Material You / accent) where possible.
/// Secondary: soft relaxing seeds chosen for low stimulation and positive feel.
class BnsTheme {
  static const _pillMorning = Color(0xFFFDE047);
  static const _pillNoon = Color(0xFFFB923C);
  static const _pillNight = Color(0xFFA855F7);

  static ThemeData build({
    required RelaxingPalette palette,
    required ThemeModeSetting mode,
    ColorScheme? dynamicLight,
    ColorScheme? dynamicDark,
  }) {
    final base = _seedForPalette(palette);

    // GOOD COLORS ARE PART OF THE CARE (owner, 2026-08-15: "its color is
    // depressing… they are sick colors"). Material's default fromSeed
    // washes every seed toward gray — in dark mode that meant near-black
    // rooms with muted teal ghosts. Two changes give the app its life:
    //   1. `fidelity` keeps the chroma of the chosen palette instead of
    //      averaging it away;
    //   2. surfaces get their own tone — dark rooms lift off pure black
    //      into a soft palette-tinted deep, light rooms warm off the
    //      sterile white. Same relaxing hues, actually visible.
    // Dynamic color (the person's own Material You) stays untouched.
    final light = dynamicLight ?? _lively(base, Brightness.light);
    final dark = dynamicDark ?? _lively(base, Brightness.dark);

    final isDark = mode == ThemeModeSetting.dark ||
        (mode == ThemeModeSetting.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: isDark ? dark : light,
      // STATIC transitions on every platform and every navigation path
      // (go_router pages AND plain Navigator.push both honor this).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _StaticTransitionsBuilder(),
          TargetPlatform.iOS: _StaticTransitionsBuilder(),
          TargetPlatform.windows: _StaticTransitionsBuilder(),
          TargetPlatform.macOS: _StaticTransitionsBuilder(),
          TargetPlatform.linux: _StaticTransitionsBuilder(),
          TargetPlatform.fuchsia: _StaticTransitionsBuilder(),
        },
      ),
      // Soft rounded like PillMemorizer but gentler
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
      ),
      // Generous touch targets for motor / memory friendliness
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16))),
        ),
      ),
    );
  }

  /// A scheme that keeps the palette's life, with rooms that are neither
  /// black holes nor hospital white.
  static ColorScheme _lively(Color seed, Brightness brightness) {
    final s = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    if (brightness == Brightness.dark) {
      // Lift off pure black into a soft deep tinted by the palette —
      // the difference between a cave and an evening room.
      Color lift(double a) =>
          Color.alphaBlend(seed.withValues(alpha: a), const Color(0xFF171D1B));
      return s.copyWith(
        surface: lift(0.045),
        surfaceContainerLowest: lift(0.03),
        surfaceContainerLow: lift(0.075),
        surfaceContainer: lift(0.10),
        surfaceContainerHigh: lift(0.13),
        surfaceContainerHighest: lift(0.16),
      );
    }
    // Light: warm the paper a touch so white stops feeling clinical.
    Color warm(double a) =>
        Color.alphaBlend(seed.withValues(alpha: a), const Color(0xFFFBFAF7));
    return s.copyWith(
      surface: warm(0.015),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: warm(0.045),
      surfaceContainer: warm(0.065),
      surfaceContainerHigh: warm(0.09),
      surfaceContainerHighest: warm(0.12),
    );
  }

  static Color _seedForPalette(RelaxingPalette p) {
    switch (p) {
      case RelaxingPalette.teal:
        // A touch brighter than the old 0xFF14B8A6 — alive, still calm.
        return const Color(0xFF17C3A8);
      case RelaxingPalette.lavender:
        return const Color(0xFF9B7BF7);
      case RelaxingPalette.sand:
        return const Color(0xFFE8930C);
      case RelaxingPalette.deep:
        // Was a gray slate — a gloom, not a palette. Now a calm sea blue.
        return const Color(0xFF4A7DE0);
    }
  }

  /// The gentle colors a reminder may wear — chosen by the person
  /// (settings.notificationColor). Also used by the settings color chips.
  /// All soft, none alarming; there is deliberately no red.
  static const Map<String, Color> reminderColors = {
    'teal': Color(0xFF14B8A6),
    'lavender': Color(0xFF8B5CF6),
    'green': Color(0xFF22C55E),
    'amber': Color(0xFFF59E0B),
    'rose': Color(0xFFF472B6),
    'sky': Color(0xFF38BDF8),
  };

  /// The color reminders arrive in, by the like of the user:
  /// 'auto' follows the app's own relaxing palette, anything else is one of
  /// [reminderColors]. Unknown values fall back to the palette seed, so an
  /// old .bns from a newer app never breaks anything.
  static Color reminderColor(AppSettings s) {
    if (s.notificationColor != 'auto') {
      final named = reminderColors[s.notificationColor];
      if (named != null) return named;
    }
    return _seedForPalette(s.relaxingPalette);
  }

  // Reusable category tints inspired directly by PillMemorizer timeline
  static Color categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'morning':
        return _pillMorning;
      case 'noon':
      case 'midday':
        return _pillNoon;
      case 'evening':
      case 'night':
        return _pillNight;
      default:
        return Colors.tealAccent;
    }
  }
}
