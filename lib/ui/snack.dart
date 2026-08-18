import 'package:flutter/material.dart';

/// ONE TOAST AT A TIME — owner law (2026-08-18): "יש ספאם של טוסטים מכל
/// מיני כפתורים, אסור שיהיה מצב כזה."
///
/// ScaffoldMessenger QUEUES snack bars: five taps meant five toasts
/// playing one after another long after the person moved on — for a
/// low-cognitive-load app that is noise wearing a uniform. Every BNS
/// feedback toast goes through here: the newest replaces whatever was
/// showing or waiting, nothing ever lines up.
///
/// The one deliberate exception is the desktop REMINDER card
/// (desktop_reminder_service.dart) — that is a reminder surface with
/// actions, not tap feedback, and it keeps the plain messenger.
class BnsSnack {
  BnsSnack._();

  static void show(BuildContext context, SnackBar bar) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(bar);
  }
}
