import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

enum RecurrenceType {
  daily,
  weekdays,
  weekly,
  custom,
}

@freezed
@Collection()
class Routine with _$Routine {
  const Routine._();

  const factory Routine({
    @Index(unique: true) required String id, // UUID
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    // For weekly / custom: 0=Sun ... 6=Sat. Empty means all for daily.
    List<int> daysOfWeek,
    String? time, // "HH:mm" local, optional
    @Default(true) bool isActive,
    @Default([]) List<String> tags,
    @Default(false) bool firstStepOnlyDefault,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Routine;

  factory Routine.fromJson(Map<String, dynamic> json) => _$RoutineFromJson(json);

  // Convenience: does this routine apply on a given local date?
  bool appliesOn(DateTime date) {
    if (!isActive) return false;
    final dow = date.weekday % 7; // 0=Sun ... 6=Sat to match our convention

    switch (recurrenceType) {
      case RecurrenceType.daily:
        return true;
      case RecurrenceType.weekdays:
        return dow >= 1 && dow <= 5;
      case RecurrenceType.weekly:
      case RecurrenceType.custom:
        return daysOfWeek.contains(dow);
    }
  }
}
