import 'package:bns/core/models/routine.dart';

/// Helpers for filtering routines that apply today / on a date.
/// Mirrors forgiving daily logic from PillMemorizer (grace periods etc. will live in repository).
class RecurrenceUtils {
  static List<Routine> routinesForDate(List<Routine> all, DateTime date) {
    return all.where((r) => r.appliesOn(date)).toList();
  }

  static List<Routine> routinesForToday(List<Routine> all) =>
      routinesForDate(all, DateTime.now());

  /// Simple string for display, e.g. "Daily • 08:15" or "Weekdays"
  static String describe(Routine r) {
    final time = r.time != null ? ' • ${r.time}' : '';
    switch (r.recurrenceType) {
      case RecurrenceType.daily:
        return 'Daily$time';
      case RecurrenceType.weekdays:
        return 'Weekdays$time';
      case RecurrenceType.weekly:
        return 'Weekly$time';
      case RecurrenceType.custom:
        final days = r.daysOfWeek.map(_dowLabel).join(',');
        return 'Custom ($days)$time';
    }
  }

  static String _dowLabel(int d) => ['S','M','T','W','T','F','S'][d];
}
