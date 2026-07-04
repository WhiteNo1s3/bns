import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'completion_log.freezed.dart';
part 'completion_log.g.dart';

enum CompletionStatus { done, skipped }

@freezed
@Collection()
class CompletionLog with _$CompletionLog {
  const CompletionLog._();

  const factory CompletionLog({
    @Index(unique: true) required String id,
    required String routineId,
    required String date, // YYYY-MM-DD
    required CompletionStatus status,
    String? reason,
    String? reasonAudioPath,
    required DateTime at,
  }) = _CompletionLog;

  factory CompletionLog.fromJson(Map<String, dynamic> json) =>
      _$CompletionLogFromJson(json);
}
