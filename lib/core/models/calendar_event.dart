/// Plain, dependency-free model (no codegen).
library;

const Object _unset = Object();

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

  // A plan CARRIES WEIGHT (owner, 2026-08-09): a doctor appointment or a
  // one-time thing for today stands in the day like a gentle step — it can
  // be answered. null = still open; 'done' = the quiet ✓; 'skipped' =
  // "didn't happen", stated out loud, never faked into a checkmark.
  // One-time by nature, so the answer lives on the plan itself (no
  // per-date log bookkeeping like routines need).
  final String? answer;
  final String? answerReason; // the kept "why" when it didn't happen
  final DateTime? answerAt;

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
    this.answer,
    this.answerReason,
    this.answerAt,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isDone => answer == 'done';
  bool get isSkipped => answer == 'skipped';
  bool get isAnswered => answer != null;

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? date,
    Object? time = _unset,
    Object? notes = _unset,
    bool? isAllDay,
    bool? shareWithFamily,
    Object? answer = _unset,
    Object? answerReason = _unset,
    Object? answerAt = _unset,
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
      answer: answer == _unset ? this.answer : answer as String?,
      answerReason:
          answerReason == _unset ? this.answerReason : answerReason as String?,
      answerAt: answerAt == _unset ? this.answerAt : answerAt as DateTime?,
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
        'answer': answer,
        'answerReason': answerReason,
        'answerAt': answerAt?.toIso8601String(),
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
        answer: json['answer'] as String?,
        answerReason: json['answerReason'] as String?,
        answerAt: json['answerAt'] == null
            ? null
            : DateTime.tryParse(json['answerAt'] as String),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
