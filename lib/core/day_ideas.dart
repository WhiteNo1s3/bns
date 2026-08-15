/// Ideas gathered for a calendar day — written when you remember,
/// waiting if tomorrow is a blackout.
library;

import 'package:bns/core/models/quick_capture.dart';

String calendarDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Where this note lives on the calendar.
/// [forDate] wins (tonight's Haifa bag belongs to tomorrow).
/// Otherwise the day it was recorded.
bool captureBelongsToDate(QuickCapture c, DateTime date) {
  final key = calendarDateKey(date);
  final pinned = (c.forDate ?? '').trim();
  if (pinned.isNotEmpty) return pinned == key;
  return c.at.year == date.year &&
      c.at.month == date.month &&
      c.at.day == date.day;
}
