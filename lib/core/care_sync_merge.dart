/// Directed merge across the care wall — one law, every level.
///
/// From AGENTS.md and docs/care-levels.md, plus the 2026-08-18 owner
/// picture (TBI / DAI: they have a life, not a helper-only list):
///
///   1 Independent — they build the day and the future. Care may ADD
///     upcoming facts (cousin birthday Saturday) so the calendar stays
///     real, and may refresh those facts. Care must not replace the
///     routine they set.
///   2 Family — same ownership of planning. Care may UPDATE chosen
///     family upcoming (the daily "Saturday is still coming") and ADD
///     facts. Private untagged routines stay the person's.
///   3 Full care — they can still make some changes (not a doll).
///     Plan fields last-write-wins; answers stay theirs.
///   4 Guided — Care is source of PLANNED; they only answer.
///
/// Happened (✓ / skip / gather taken / take-back) is always the
/// person's, at every level. A helper's unanswered copy is not a
/// take-back. Last-write-wins on the whole item was the closed-loop
/// bug: answering bumped [updatedAt], so a Care edit wiped the ✓ —
/// or the ✓ hid Saturday's update.
library;

import 'package:bns/core/models/models.dart';
import 'package:bns/core/need_help.dart';

/// The person's band on THIS merge — the helper's own healed
/// [AppSettings.careLevel] is never the story.
enum PersonCareBand {
  /// Level 1 — they make the day and the future.
  independent,

  /// Level 2 — they make the day; family-chosen upcoming can be refreshed.
  family,

  /// Level 3 — they can still change things; Care can too.
  fullCare,

  /// Level 4 — Care builds; they answer.
  guided,
}

PersonCareBand personCareBand({
  required int careLevel,
  required bool guidedMode,
  required bool fullCareMode,
}) {
  if (guidedMode || careLevel >= 4) return PersonCareBand.guided;
  if (fullCareMode || careLevel == 3) return PersonCareBand.fullCare;
  if (careLevel == 2) return PersonCareBand.family;
  return PersonCareBand.independent;
}

/// Whose file is [incoming]? A care-window stub (empty deviceId) is
/// always the person's day toward a helper — never a helper dump.
bool incomingIsFromHelper(AppSettings incoming) {
  if (incoming.deviceId.isEmpty) return false;
  return incoming.caregiverDevice;
}

/// The person this conversation is about. On their device, that is
/// local. On Care, a full person snapshot carries the flags; a window
/// stub does not, so we use last-write on plans (receive-first safe).
PersonCareBand bandForMerge({
  required AppSettings local,
  required AppSettings incoming,
}) {
  if (!local.caregiverDevice) {
    return personCareBand(
      careLevel: local.careLevel,
      guidedMode: local.guidedMode,
      fullCareMode: local.fullCareMode,
    );
  }
  if (incoming.deviceId.isEmpty) return PersonCareBand.fullCare;
  return personCareBand(
    careLevel: incoming.careLevel,
    guidedMode: incoming.guidedMode,
    fullCareMode: incoming.fullCareMode,
  );
}

/// True when the helper's PLAN fields should replace the local ones.
///
/// Events are upcoming facts (Saturday). Routines are the day they set.
bool adoptHelperPlan({
  required bool incomingFromHelper,
  required bool incomingNewer,
  required PersonCareBand band,
  required bool isEvent,
  required bool familyShared,
  bool helperSeed = false,
  bool personEditedRoutine = false,
}) {
  if (!incomingFromHelper) return incomingNewer;
  if (helperSeed) return false;
  switch (band) {
    case PersonCareBand.guided:
      return true;
    case PersonCareBand.fullCare:
      return incomingNewer;
    case PersonCareBand.family:
    case PersonCareBand.independent:
      if (isEvent) return incomingNewer;
      // They set their routine. Care may GIVE a new one (no local row).
      // An existing routine is overwritten only when they never touched
      // it (Care-given, still fresh) or they chose to share it at L2.
      if (personEditedRoutine) return false;
      return familyShared && incomingNewer;
  }
}

CalendarEvent mergeDirectedEvent({
  required CalendarEvent? local,
  required CalendarEvent incoming,
  required bool incomingFromHelper,
  required PersonCareBand band,
}) {
  if (local == null) return incoming;

  final takeIncomingPlan = adoptHelperPlan(
    incomingFromHelper: incomingFromHelper,
    incomingNewer: incoming.updatedAt.isAfter(local.updatedAt),
    band: band,
    isEvent: true,
    familyShared: incoming.shareWithFamily || local.shareWithFamily,
    helperSeed: incomingFromHelper && incoming.id.startsWith('seed-'),
  );
  final plan = takeIncomingPlan ? incoming : local;
  final answers = mergeEventAnswers(
    local: local,
    incoming: incoming,
    incomingFromHelper: incomingFromHelper,
  );
  final personGather = incomingFromHelper ? local.gather : incoming.gather;
  final otherGather = incomingFromHelper ? incoming.gather : local.gather;
  return plan.copyWith(
    answer: answers.answer,
    answerReason: answers.reason,
    answerAt: answers.at,
    gather: mergeGather(
      planItems: plan.gather,
      personItems: personGather,
      otherItems: otherGather,
    ),
    updatedAt: plan.updatedAt,
    createdAt: local.createdAt,
  );
}

({String? answer, String? reason, DateTime? at}) mergeEventAnswers({
  required CalendarEvent local,
  required CalendarEvent incoming,
  required bool incomingFromHelper,
}) {
  final person = incomingFromHelper ? local : incoming;
  final helperCopy = incomingFromHelper ? incoming : local;
  final pAt = person.answerAt;
  final hAt = helperCopy.answerAt;
  if (pAt != null && (hAt == null || !hAt.isAfter(pAt))) {
    return (answer: person.answer, reason: person.answerReason, at: pAt);
  }
  if (hAt != null && (pAt == null || hAt.isAfter(pAt))) {
    // Forwarded from the person (or their other device) via receive-first.
    return (
      answer: helperCopy.answer,
      reason: helperCopy.answerReason,
      at: hAt
    );
  }
  if (person.answer != null) {
    return (
      answer: person.answer,
      reason: person.answerReason,
      at: person.answerAt
    );
  }
  return (
    answer: helperCopy.answer,
    reason: helperCopy.answerReason,
    at: helperCopy.answerAt
  );
}

/// Plan items from the adopted plan; [takenAt] from the person.
List<GatherItem> mergeGather({
  required List<GatherItem> planItems,
  required List<GatherItem> personItems,
  required List<GatherItem> otherItems,
}) {
  DateTime? takenAtFor(String id) {
    for (final g in personItems) {
      if (g.id == id && g.takenAt != null) return g.takenAt;
    }
    for (final g in otherItems) {
      if (g.id == id && g.takenAt != null) return g.takenAt;
    }
    return null;
  }

  return [
    for (final g in planItems) g.copyWith(takenAt: takenAtFor(g.id)),
  ];
}

bool routineWasEditedByPerson(Routine r) =>
    r.updatedAt.difference(r.createdAt).inSeconds > 1;

Routine mergeDirectedRoutine({
  required Routine? local,
  required Routine incoming,
  required bool incomingFromHelper,
  required PersonCareBand band,
}) {
  if (local == null) return incoming;

  final takeIncomingPlan = adoptHelperPlan(
    incomingFromHelper: incomingFromHelper,
    incomingNewer: incoming.updatedAt.isAfter(local.updatedAt),
    band: band,
    isEvent: false,
    familyShared:
        level2ShareAllowsRoutine(local) || level2ShareAllowsRoutine(incoming),
    helperSeed: incomingFromHelper && incoming.id.startsWith('seed-'),
    personEditedRoutine: routineWasEditedByPerson(local),
  );
  final plan = takeIncomingPlan ? incoming : local;
  final timeByDay = <String, String>{...plan.timeByDay};
  if (incomingFromHelper) {
    timeByDay.addAll(local.timeByDay);
  } else {
    timeByDay.addAll(incoming.timeByDay);
  }
  return plan.copyWith(
    timeByDay: timeByDay,
    updatedAt: plan.updatedAt,
    createdAt: local.createdAt,
  );
}

/// Logs are what HAPPENED. A helper cannot invent or restore them.
/// When the incoming file is the person, their (routine, day) row wins.
List<CompletionLog> mergeDirectedLogs({
  required List<CompletionLog> local,
  required List<CompletionLog> incoming,
  required bool incomingFromHelper,
  required bool incomingIsFullPerson,
}) {
  if (incomingFromHelper) return List<CompletionLog>.from(local);

  final out = <String, CompletionLog>{};
  for (final l in local) {
    out['${l.routineId}|${l.date}'] = l;
  }
  for (final l in incoming) {
    out['${l.routineId}|${l.date}'] = l;
  }
  if (incomingIsFullPerson) {
    final keep = {for (final l in incoming) '${l.routineId}|${l.date}'};
    out.removeWhere((k, _) => !keep.contains(k));
  }
  return out.values.toList();
}

bool sameGatherBag(List<GatherItem> a, List<GatherItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id || a[i].text != b[i].text) return false;
  }
  return true;
}
