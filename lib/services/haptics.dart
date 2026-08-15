/// THE PHONE ANSWERS THE FINGER (owner QA, 2026-08-15: "the gesture to long
/// press suppose to make it more responsive").
///
/// Long-press is how a person says "this didn't happen" — and it used to
/// give NOTHING back while the finger was held: no buzz, no mark, just
/// silence until a sheet appeared half a second later. Silence reads as
/// "the app didn't hear me", so the finger lifts early and the gesture
/// never lands. One short buzz the instant it registers turns the same
/// 500ms into something that feels immediate.
///
/// `hapticsEnabled` has been in settings since the beginning and was wired
/// to nothing at all — this is what it was always meant to do. Quiet days
/// turn it off like everything else.
library;

import 'package:flutter/services.dart';

import 'package:bns/data/local/isar_service.dart';

class BnsHaptics {
  BnsHaptics._();

  /// Cached so a buzz is never waiting on a disk read — the whole point is
  /// that it happens in the same instant as the finger.
  static bool _enabled = true;
  static bool _loaded = false;

  /// Read the person's choice. Safe to call more than once.
  static Future<void> init() async {
    try {
      _enabled = (await IsarService.getSettings()).hapticsEnabled;
      _loaded = true;
    } catch (_) {
      // A missing setting must never cost the app a gesture.
    }
  }

  /// Settings changed somewhere — pick the new answer up quietly.
  static void refresh() {
    if (!_loaded) return;
    IsarService.getSettings().then((s) => _enabled = s.hapticsEnabled).catchError(
        (_) => _enabled);
  }

  /// "I heard you" — the moment a long-press registers. Fire-and-forget so
  /// nothing waits on the platform channel.
  static void longPress() {
    if (!_enabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// A lighter tick for small confirmations.
  static void tick() {
    if (!_enabled) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }
}
