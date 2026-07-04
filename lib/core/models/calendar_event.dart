import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'calendar_event.freezed.dart';
part 'calendar_event.g.dart';

@freezed
@Collection()
class CalendarEvent with _$CalendarEvent {
  const CalendarEvent._();

  const factory CalendarEvent({
    @Index(unique: true) required String id,
    required String title,
    required String date, // YYYY-MM-DD local
    String? time,         // HH:mm optional
    String? notes,
    @Default(false) bool isAllDay,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _CalendarEvent;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) =>
      _$CalendarEventFromJson(json);
}
