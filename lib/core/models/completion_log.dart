/// Plain, dependency-free model (no codegen).
library;

enum CompletionStatus { done, skipped }

const Object _unset = Object();

class CompletionLog {
  final String id;
  final String routineId;
  final String date; // YYYY-MM-DD
  final CompletionStatus status;
  final String? reason;
  final String? reasonAudioPath;
  final DateTime at;

  const CompletionLog({
    required this.id,
    required this.routineId,
    required this.date,
    required this.status,
    this.reason,
    this.reasonAudioPath,
    required this.at,
  });

  CompletionLog copyWith({
    String? id,
    String? routineId,
    String? date,
    CompletionStatus? status,
    Object? reason = _unset,
    Object? reasonAudioPath = _unset,
    DateTime? at,
  }) {
    return CompletionLog(
      id: id ?? this.id,
      routineId: routineId ?? this.routineId,
      date: date ?? this.date,
      status: status ?? this.status,
      reason: reason == _unset ? this.reason : reason as String?,
      reasonAudioPath: reasonAudioPath == _unset
          ? this.reasonAudioPath
          : reasonAudioPath as String?,
      at: at ?? this.at,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'routineId': routineId,
        'date': date,
        'status': status.name,
        'reason': reason,
        'reasonAudioPath': reasonAudioPath,
        'at': at.toIso8601String(),
      };

  factory CompletionLog.fromJson(Map<String, dynamic> json) => CompletionLog(
        id: json['id'] as String? ?? '',
        routineId: json['routineId'] as String? ?? '',
        date: json['date'] as String? ?? '',
        status: CompletionStatus.values.asNameMap()[json['status']] ??
            CompletionStatus.done,
        reason: json['reason'] as String?,
        reasonAudioPath: json['reasonAudioPath'] as String?,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      );
}
