import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/routine.dart';

/// Helpers for filtering routines that apply today / on a date.
/// Mirrors forgiving daily logic from PillMemorizer (grace periods etc. will live in repository).
class RecurrenceUtils {
  static List<Routine> routinesForDate(List<Routine> all, DateTime date) {
    return all.where((r) => r.appliesOn(date)).toList();
  }

  static List<Routine> routinesForToday(List<Routine> all) =>
      routinesForDate(all, DateTime.now());

  /// The line under a routine's name, in the PERSON'S language.
  ///
  /// This read "Daily • 08:00" on a Hebrew screen — English sitting on
  /// every tile of a Hebrew-first app, found by using it (owner QA,
  /// 2026-08-15). The weekday initials were English too, so a custom
  /// routine said "Custom (S,M,T)" to someone reading right-to-left.
  static String describe(Routine r) {
    final time = r.time != null ? ' • ${r.time}' : '';
    switch (r.recurrenceType) {
      case RecurrenceType.daily:
        return L.t('Every day$time', 'כל יום$time');
      case RecurrenceType.weekdays:
        return L.t('Weekdays$time', 'ימי חול$time');
      case RecurrenceType.weekly:
        return L.t('Every week$time', 'כל שבוע$time');
      case RecurrenceType.custom:
        final days = (r.daysOfWeek.toList()..sort()).map(_dowLabel).join(', ');
        return L.t('On $days$time', 'בימים $days$time');
    }
  }

  /// 0=Sunday … 6=Saturday — the app's convention. Hebrew names its days
  /// by letter the way a calendar here does (א׳, ב׳ … שבת).
  static String _dowLabel(int d) {
    final i = d.clamp(0, 6);
    return L.isHebrew
        ? const ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'שבת'][i]
        : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][i];
  }
}
