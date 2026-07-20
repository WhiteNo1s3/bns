/// Plain, dependency-free model (no codegen).
library;

const Object _unset = Object();

class CalendarEvent {
  final String id;
  final String title;
  final String date; // YYYY-MM-DD local (start day)
  final String? time; // HH:mm optional
  final String? notes;
  final bool isAllDay;
  // "Family can know": marked by the user on IMPORTANT things he might
  // forget (doctor meeting, wedding, holiday). Only these events ever enter
  // the family-share export — the rest is none of their business (owner
  // decision, 2026-07-06).
  final bool shareWithFamily;

  // --- Special order (owner, 2026-07-20) ---
  // Out of the ordinary: laptop fix drive, month away, anything that
  // disrupts the usual system. Not a repeating routine. User-facing words
  // stay plain ("Something different") — never clinical.
  final bool isSpecialOrder;
  // Inclusive end day for multi-day special orders (null = single day).
  final String? endDate;
  // System-breaking: usual list can wait / go soft while this is on.
  final bool disruptive;
  // Who is coming along for cold feet ("parents are driving with me").
  final String? companionNote;

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
    this.isSpecialOrder = false,
    this.endDate,
    this.disruptive = false,
    this.companionNote,
    required this.createdAt,
    required this.updatedAt,
  });

  /// True when [dayYmd] (YYYY-MM-DD) falls on this event's day or span.
  bool activeOn(String dayYmd) {
    if (dayYmd == date) return true;
    final end = endDate;
    if (end == null || end.isEmpty) return false;
    return dayYmd.compareTo(date) >= 0 && dayYmd.compareTo(end) <= 0;
  }

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? date,
    Object? time = _unset,
    Object? notes = _unset,
    bool? isAllDay,
    bool? shareWithFamily,
    bool? isSpecialOrder,
    Object? endDate = _unset,
    bool? disruptive,
    Object? companionNote = _unset,
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
      isSpecialOrder: isSpecialOrder ?? this.isSpecialOrder,
      endDate: endDate == _unset ? this.endDate : endDate as String?,
      disruptive: disruptive ?? this.disruptive,
      companionNote: companionNote == _unset
          ? this.companionNote
          : companionNote as String?,
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
        'isSpecialOrder': isSpecialOrder,
        'endDate': endDate,
        'disruptive': disruptive,
        'companionNote': companionNote,
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
        isSpecialOrder: json['isSpecialOrder'] as bool? ?? false,
        endDate: json['endDate'] as String?,
        disruptive: json['disruptive'] as bool? ?? false,
        companionNote: json['companionNote'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
