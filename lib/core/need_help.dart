/// Level-1 close circuit: the person can ASK for help.
///
/// Care vision (owner law):
///   1 Independent — nothing leaves except a Need-help tag they opened.
///   2 Family knows chosen plans only (plus an opened Need-help ask).
///   3 Full care — family sees everything; they monitor, they do not edit.
///   4 Guided — the person sees ONLY the list; the inspector builds the day.
///
/// A skip, a late tick, a mood, a location, or silence is NEVER an ask.
/// The person opens the tag. That is the only Level-1 share.
library;

import 'package:bns/core/models/calendar_event.dart';
import 'package:bns/core/models/quick_capture.dart';
import 'package:bns/core/models/routine.dart';

/// On a routine or plan: they tagged this one.
const kNeedHelpTag = 'need-help';

/// On the capture that travels: an explicit ask, not a skip note.
const kAskedHelpTag = 'asked-help';

bool isMadVentTag(Iterable<String> tags) =>
    tags.any((t) => t.toLowerCase().replaceAll('#', '').trim() == 'mad-vent');

bool _has(Iterable<String> tags, String name) => tags.any(
    (t) => t.toLowerCase().replaceAll('#', '').trim() == name.toLowerCase());

/// True when this capture is an opened Need-help ask (Level 1 share).
bool isAskedHelpCapture(QuickCapture c) {
  if (c.deletedAt != null) return false;
  if (isMadVentTag(c.tags)) return false;
  return _has(c.tags, kAskedHelpTag);
}

/// Skip-derived notes stay tagged `need-help` for the day diary.
/// They must never look like an opened ask.
bool isSkipNoteNotAnAsk(QuickCapture c) =>
    _has(c.tags, kNeedHelpTag) && !isAskedHelpCapture(c);

bool routineNeedsHelp(Routine r) => _has(r.tags, kNeedHelpTag);

bool planNeedsHelp(CalendarEvent e) => e.needHelp;

String needHelpLabel({required bool hebrew}) =>
    hebrew ? 'צריך עזרה' : 'Need help';

/// The Level-1 sentence that family sees. Nothing else is implied.
String askedHelpShareLine({required bool hebrew}) =>
    hebrew ? 'ביקשתי עזרה בזה.' : 'I asked for help on this.';

/// What a trusted family device is told — distinct from ordinary sync.
String askedHelpNotifyBody(String aboutTitle, {required bool hebrew}) {
  final line = askedHelpShareLine(hebrew: hebrew);
  final about = aboutTitle.trim();
  if (about.isEmpty) return line;
  return '$line $about';
}

/// New asks that arrived in [after] and were not in [before].
/// Ordinary day activity (skip / diary / tick) does not appear here.
List<QuickCapture> newAskedHelpCaptures({
  required Iterable<QuickCapture> before,
  required Iterable<QuickCapture> after,
}) {
  final seen = before.where(isAskedHelpCapture).map((c) => c.id).toSet();
  return after.where(isAskedHelpCapture).where((c) => !seen.contains(c.id)).toList();
}

/// What Level 1 may put in a family file: only opened asks.
bool level1ShareAllows(QuickCapture c) => isAskedHelpCapture(c);

/// Build the capture that rides the family file and the LAN notify.
QuickCapture buildAskedHelpCapture({
  required String id,
  required DateTime at,
  required String aboutTitle,
  String? linkedRoutineId,
  String? linkedEventId,
  required bool hebrew,
}) {
  final line = askedHelpShareLine(hebrew: hebrew);
  final about = aboutTitle.trim();
  return QuickCapture(
    id: id,
    at: at,
    text: about.isEmpty ? line : '$line\n$about',
    linkedRoutineId: linkedRoutineId,
    linkedEventId: linkedEventId,
    tags: const [kAskedHelpTag, kNeedHelpTag, 'family'],
    memoryLevel: MemoryLevel.remember,
    contextNote: about.isEmpty ? null : about,
  );
}

/// Toggle the Need-help tag on a routine's tag list.
List<String> toggleNeedHelpTag(List<String> tags, {required bool on}) {
  final next = [
    for (final t in tags)
      if (t.toLowerCase().replaceAll('#', '').trim() != kNeedHelpTag) t
  ];
  if (on) next.add(kNeedHelpTag);
  return next;
}

/// Which picture leaves toward a caregiver / family window.
/// Own devices (peer is not caregiver) always get the full day.
enum FamilyShareLevel {
  /// Level 1: only opened Need-help asks (+ the named routine/plan).
  asksOnly,

  /// Level 2: chosen family plans + family-tagged moments + asks.
  chosenFamily,

  /// Level 3–4: everything the people who care need (monitor, not edit).
  fullCare,
}

FamilyShareLevel familyShareLevelFor(int careLevel, {required bool fullCareMode}) {
  if (careLevel >= 3 || fullCareMode) return FamilyShareLevel.fullCare;
  if (careLevel == 2) return FamilyShareLevel.chosenFamily;
  return FamilyShareLevel.asksOnly;
}
