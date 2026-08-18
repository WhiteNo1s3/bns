/// CARE ALARM — one time, every person this seat helps, on THEIR clock.
///
/// The helper sets a ring once. Each Care profile gets its own copy.
/// It fires on that person's device, at that HH:mm on *their* wall clock
/// (`tz.local` there — never the helper's phone time, never NTP).
///
/// This phone does not ring. An alarm is a plan, not an answer.
/// Levels 1–2 own their day: a wake they already set stays theirs;
/// an empty nightstand may receive this so they can live toward it.
/// Levels 3–4: the helper's set time is an instruction on their clock.
library;

/// Which side of a merge keeps the wake — time and note travel together.
enum WakeAdopt { incoming, local }

/// Empty string is unset (like hour 0 on the person-day clock). A
/// helper's empty is never a choice — it must not wipe a wake they
/// already have. Outside full care they own their day.
WakeAdopt wakeAdoptChoice({
  required String incomingTime,
  required String localTime,
  bool incomingIsHelper = false,
  bool localUnderFullCare = false,
}) {
  final incoming = incomingTime.trim();
  final local = localTime.trim();
  if (incomingIsHelper) {
    if (incoming.isEmpty) return WakeAdopt.local;
    if (localUnderFullCare) return WakeAdopt.incoming;
    return local.isEmpty ? WakeAdopt.incoming : WakeAdopt.local;
  }
  if (incoming.isEmpty && local.isNotEmpty) return WakeAdopt.local;
  return WakeAdopt.incoming;
}

({String time, String note}) adoptWakeFields({
  required String incomingTime,
  required String incomingNote,
  required String localTime,
  required String localNote,
  bool incomingIsHelper = false,
  bool localUnderFullCare = false,
}) {
  final which = wakeAdoptChoice(
    incomingTime: incomingTime,
    localTime: localTime,
    incomingIsHelper: incomingIsHelper,
    localUnderFullCare: localUnderFullCare,
  );
  return which == WakeAdopt.incoming
      ? (time: incomingTime.trim(), note: incomingNote)
      : (time: localTime, note: localNote);
}

String adoptWakeAlarm({
  required String incoming,
  required String local,
  bool incomingIsHelper = false,
  bool localUnderFullCare = false,
}) =>
    adoptWakeFields(
      incomingTime: incoming,
      incomingNote: '',
      localTime: local,
      localNote: '',
      incomingIsHelper: incomingIsHelper,
      localUnderFullCare: localUnderFullCare,
    ).time;

/// One person this seat can reach — their door, their clock, their wake.
class CareAlarmSeat {
  final String profileId;
  final String name;
  final String wakeTime;
  final String wakeNote;
  final int dayStartHour;
  final int dayRolloverHour;
  final bool paired;

  const CareAlarmSeat({
    required this.profileId,
    required this.name,
    this.wakeTime = '',
    this.wakeNote = '',
    this.dayStartHour = 0,
    this.dayRolloverHour = 0,
    this.paired = false,
  });
}

String _hh(int hour) => '${hour.toString().padLeft(2, '0')}:00';

/// What the helper reads for one person. Times are that person's
/// wall clock. A different existing wake is named so Saturday 8:00
/// is still a fact, without pretending we overwrote their day.
String careAlarmSeatLine({
  required CareAlarmSeat seat,
  required String sentTime,
  required String Function(String en, String he) t,
}) {
  final who = seat.name.trim().isEmpty
      ? t('Someone you help', 'מי שאתה מלווה')
      : seat.name.trim();
  if (!seat.paired) {
    return t(
      '$who — not paired yet. It is sent after pairing.',
      '$who — אין חיבור עדיין. יישלח לאחר הצימוד.',
    );
  }
  if (seat.wakeTime.isNotEmpty && seat.wakeTime != sentTime) {
    return t(
      '$who — currently ${seat.wakeTime}. At levels 1–2 their own setting comes first.',
      '$who — כרגע ${seat.wakeTime}. ברמות 1–2 ההגדרה שלהם קודמת.',
    );
  }
  return t('$who — $sentTime on their clock.', '$who — $sentTime על השעון שלהם.');
}

/// Their day start, when it is a chosen hour. 0 is unset, not a claim.
String? careAlarmDayStartLine({
  required CareAlarmSeat seat,
  required String Function(String en, String he) t,
}) {
  if (seat.dayStartHour == 0) return null;
  return t(
    'Their day starts ${_hh(seat.dayStartHour)}.',
    'היום שלהם מתחיל ${_hh(seat.dayStartHour)}.',
  );
}
