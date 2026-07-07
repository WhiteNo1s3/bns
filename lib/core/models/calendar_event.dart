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
    required this.createdAt,
    required this.updatedAt,
  });

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? date,
    Object? time = _unset,
    Object? notes = _unset,
    bool? isAllDay,
    bool? shareWithFamily,
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
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
