/// Plain, dependency-free model (no codegen).
/// JSON <-> model is hand-written so `.bns` files stay stable and readable.
library;

enum RecurrenceType {
  daily,
  weekdays,
  weekly,
  custom,
}

const Object _unset = Object();

/// One PART of a routine — its own entity, its own information (owner,
/// 2026-07-08: "an entity for each part of the routine… a list of classes
/// for the activity, where we put the information"). These are the trees
/// inside the action: "Morning meds" → [take pills, drink water, check BP].
class RoutineStep {
  final String title;
  final String? note; // the information that helps with this part

  const RoutineStep({required this.title, this.note});

  Map<String, dynamic> toJson() => {'title': title, 'note': note};

  factory RoutineStep.fromJson(Map<String, dynamic> json) => RoutineStep(
        title: json['title'] as String? ?? '',
        note: json['note'] as String?,
      );
}

class Routine {
  final String id; // UUID
  final String title;
  final String? description;
  final RecurrenceType recurrenceType;
  // For weekly / custom: 0=Sun ... 6=Sat. Empty means all for daily.
  final List<int> daysOfWeek;
  final String? time; // "HH:mm" local, optional — always on a quarter hour
  final bool isActive;
  final List<String> tags;
  final bool firstStepOnlyDefault;
  // The ordered parts of this routine (empty = a single-part routine).
  final List<RoutineStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Routine({
    required this.id,
    required this.title,
    this.description,
    required this.recurrenceType,
    this.daysOfWeek = const [],
    this.time,
    this.isActive = true,
    this.tags = const [],
    this.firstStepOnlyDefault = false,
    this.steps = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  Routine copyWith({
    String? id,
    String? title,
    Object? description = _unset,
    RecurrenceType? recurrenceType,
    List<int>? daysOfWeek,
    Object? time = _unset,
    bool? isActive,
    List<String>? tags,
    bool? firstStepOnlyDefault,
    List<RoutineStep>? steps,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Routine(
      id: id ?? this.id,
      title: title ?? this.title,
      description:
          description == _unset ? this.description : description as String?,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      time: time == _unset ? this.time : time as String?,
      isActive: isActive ?? this.isActive,
      tags: tags ?? this.tags,
      firstStepOnlyDefault: firstStepOnlyDefault ?? this.firstStepOnlyDefault,
      steps: steps ?? this.steps,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'recurrenceType': recurrenceType.name,
        'daysOfWeek': daysOfWeek,
        'time': time,
        'isActive': isActive,
        'tags': tags,
        'firstStepOnlyDefault': firstStepOnlyDefault,
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Routine.fromJson(Map<String, dynamic> json) => Routine(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String?,
        recurrenceType:
            RecurrenceType.values.asNameMap()[json['recurrenceType']] ??
                RecurrenceType.daily,
        daysOfWeek: (json['daysOfWeek'] as List? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        time: json['time'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        tags: (json['tags'] as List? ?? const []).cast<String>(),
        firstStepOnlyDefault: json['firstStepOnlyDefault'] as bool? ?? false,
        steps: (json['steps'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RoutineStep.fromJson)
            .toList(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );

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
