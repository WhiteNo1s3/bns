import 'package:flutter/widgets.dart';

/// Two languages, one app (owner, 2026-07-26): Hebrew FIRST — the first
/// users are Israeli, the TBI community doing production QA — and English
/// for the rest of the world.
///
/// Every user-facing string lives at its call site in BOTH languages:
///   Text(L.t('Diary', 'יומן'))
/// No key files, no codegen, nothing to drift out of sync — the same
/// no-codegen law the models follow. Hebrew is the default at first start;
/// the person changes it once in Settings and it stays.
class L {
  L._();

  /// 'he' or 'en'. Set from Settings at startup and on every change.
  static String lang = 'he';

  static bool get isHebrew => lang == 'he';

  static Locale get locale => Locale(lang);

  static String t(String en, String he) => isHebrew ? he : en;
}
