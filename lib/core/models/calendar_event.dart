/// Plain, dependency-free model (no codegen).
library;

const Object _unset = Object();

/// ONE THING TO TAKE — and the person is the one who ANSWERS.
///
/// Owner design, 2026-08-15, from what he watched in rehabilitation at
/// Shiba: a person who cannot gather anything themselves is still asked
/// "did we take X? did we take Y?" — and answering is the participation.
/// The professionals there treat the PERSON, not only their caregiver;
/// they hand over knowledge and a part to play instead of handling
/// someone like a doll. ריפוי בעיסוק is written off for people who
/// cannot move; at Shiba they make a version for every disability.
///
/// So this is not a packing checklist. It is a question with the person's
/// own answer on it. That is why the copy everywhere says WE — the helper
/// may carry the bag, but "we took it" belongs to both of them, and the
/// answer is the person's to give.
class GatherItem {
  final String id;

  /// What it is, in the person's own words ("תעודת זהות", "the blue folder").
  final String text;

  /// When it was answered yes. Null means "not yet" — never "failed".
  final DateTime? takenAt;

  const GatherItem({
    required this.id,
    required this.text,
    this.takenAt,
  });

  bool get taken => takenAt != null;

  GatherItem copyWith({
    String? id,
    String? text,
    Object? takenAt = _unset,
  }) =>
      GatherItem(
        id: id ?? this.id,
        text: text ?? this.text,
        takenAt: takenAt == _unset ? this.takenAt : takenAt as DateTime?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'takenAt': takenAt?.toIso8601String(),
      };

  factory GatherItem.fromJson(Map<String, dynamic> json) => GatherItem(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        takenAt: json['takenAt'] == null
            ? null
            : DateTime.tryParse(json['takenAt'] as String),
      );
}

class CalendarEvent {
  final String id;
  final String title;
  final String date; // YYYY-MM-DD local
  final String? time; // HH:mm optional
  final String? notes;
  final bool isAllDay;
  // "Family can know": marked by the user on IMPORTANT things he might
  // forget (doctor meeting, wedding, holiday). Only these events ever enter
  // the family-share export — the rest is none of their business (owner
  // decision, 2026-07-06).
  final bool shareWithFamily;
  // Opened by the person — Level 1 close circuit. Not a tracker.
  final bool needHelp;

  // A plan CARRIES WEIGHT (owner, 2026-08-09): a doctor appointment or a
  // one-time thing for today stands in the day like a gentle step — it can
  // be answered. null = still open; 'done' = the quiet ✓; 'skipped' =
  // "didn't happen", stated out loud, never faked into a checkmark.
  // One-time by nature, so the answer lives on the plan itself (no
  // per-date log bookkeeping like routines need).
  final String? answer;
  final String? answerReason; // the kept "why" when it didn't happen
  final DateTime? answerAt;

  /// What we need to take for this one. Built ahead of time — the night
  /// before, by the person or by their helper — and answered together on
  /// the day. Empty for a plan that needs nothing carried.
  final List<GatherItem> gather;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.date,
    this.time,
    this.notes,
    this.isAllDay = false,
    this.shareWithFamily = false,
    this.needHelp = false,
    this.answer,
    this.answerReason,
    this.answerAt,
    this.gather = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDone => answer == 'done';
  bool get isSkipped => answer == 'skipped';
  bool get isAnswered => answer != null;

  /// How many of the things are already with us.
  int get gatherTaken => gather.where((g) => g.taken).length;

  /// True when there is something to ask about at all.
  bool get hasGather => gather.isNotEmpty;

  /// True when every question has been answered yes — said as "ready",
  /// never as a score.
  bool get gatherReady => gather.isNotEmpty && gatherTaken == gather.length;

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? date,
    Object? time = _unset,
    Object? notes = _unset,
    bool? isAllDay,
    bool? shareWithFamily,
    bool? needHelp,
    Object? answer = _unset,
    Object? answerReason = _unset,
    Object? answerAt = _unset,
    List<GatherItem>? gather,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      time: time == _unset ? this.time : time as String?,
      notes: notes == _unset ? this.notes : notes as String?,
      isAllDay: isAllDay ?? this.isAllDay,
      shareWithFamily: shareWithFamily ?? this.shareWithFamily,
      needHelp: needHelp ?? this.needHelp,
      answer: answer == _unset ? this.answer : answer as String?,
      answerReason:
          answerReason == _unset ? this.answerReason : answerReason as String?,
      answerAt: answerAt == _unset ? this.answerAt : answerAt as DateTime?,
      gather: gather ?? this.gather,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date,
        'time': time,
        'notes': notes,
        'isAllDay': isAllDay,
        'shareWithFamily': shareWithFamily,
        'needHelp': needHelp,
        'answer': answer,
        'answerReason': answerReason,
        'answerAt': answerAt?.toIso8601String(),
        if (gather.isNotEmpty)
          'gather': gather.map((g) => g.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        date: json['date'] as String? ?? '',
        time: json['time'] as String?,
        notes: json['notes'] as String?,
        isAllDay: json['isAllDay'] as bool? ?? false,
        shareWithFamily: json['shareWithFamily'] as bool? ?? false,
        needHelp: json['needHelp'] as bool? ?? false,
        answer: json['answer'] as String?,
        answerReason: json['answerReason'] as String?,
        answerAt: json['answerAt'] == null
            ? null
            : DateTime.tryParse(json['answerAt'] as String),
        // Missing key = a plan from before gather lists existed. Every
        // .bns already out there still opens.
        gather: (json['gather'] as List? ?? const [])
            .map((g) => GatherItem.fromJson(g as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
