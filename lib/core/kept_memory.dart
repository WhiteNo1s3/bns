/// Visibility law for kept thoughts.
///
/// The person recorded it. They must be able to find it again.
///
/// Sacred:
///   * mad-vents never appear here unless [includeMad] is true
///     (active mad mode, or full-care caregiver).
///   * Trashed items stay in trash until restored.
///
/// Levels (`quick` / `remember` / `memorize`) are how LONG something
/// is kept — they are NOT a reason to hide it. A quick voice note is
/// still a memory. Hiding "quick" was the bug that made recorded
/// thoughts vanish after Save.
library;

import 'package:bns/core/models/quick_capture.dart';

/// True when this capture belongs on the person's memory list.
bool isVisibleMemory(QuickCapture c, {bool includeMad = false}) {
  if (c.deletedAt != null) return false;
  if (c.tags.contains('mad-vent') && !includeMad) return false;
  return true;
}

/// Words the person can read. Typed text first, then what the device
/// heard, then the context note. Empty means voice-only.
String memoryWords(QuickCapture c) {
  final text = (c.text ?? '').trim();
  if (text.isNotEmpty) return text;
  final heard = (c.transcript ?? '').trim();
  if (heard.isNotEmpty) return heard;
  return (c.contextNote ?? '').trim();
}

/// Newest-first list the person should see.
List<QuickCapture> visibleMemories(
  Iterable<QuickCapture> source, {
  bool includeMad = false,
}) {
  final list = source.where((c) => isVisibleMemory(c, includeMad: includeMad)).toList();
  list.sort((a, b) => b.at.compareTo(a.at));
  return list;
}

/// A new thought the person just kept. Defaults to [MemoryLevel.remember]
/// so it is shown everywhere and survives the rolling window. "Quick"
/// was the old default — it saved, then every list hid it.
MemoryLevel get defaultKeptLevel => MemoryLevel.remember;
