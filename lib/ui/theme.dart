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

    // Prefer dynamic (Android 12+/macOS) when available
    final light = dynamicLight ??
        ColorScheme.fromSeed(seedColor: base, brightness: Brightness.light);
    final dark = dynamicDark ??
        ColorScheme.fromSeed(seedColor: base, brightness: Brightness.dark);

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

  static Color _seedForPalette(RelaxingPalette p) {
    switch (p) {
      case RelaxingPalette.teal:
        return const Color(0xFF14B8A6);
      case RelaxingPalette.lavender:
        return const Color(0xFF8B5CF6);
      case RelaxingPalette.sand:
        return const Color(0xFFD97706);
      case RelaxingPalette.deep:
        return const Color(0xFF475569);
    }
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
