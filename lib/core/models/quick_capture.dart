/// Plain, dependency-free model (no codegen).
library;

enum MemoryLevel { quick, remember, memorize }

const Object _unset = Object();

class QuickCapture {
  final String id;
  final DateTime at;
  final String? text;
  final String?
      audioPath; // relative inside .bns or absolute in app docs after import
  final String? linkedRoutineId;
  final String? linkedEventId;
  final List<String> tags;
  final MemoryLevel memoryLevel;
  final String?
      contextNote; // "what happened / why the crisis or event in the routine"
  final bool isDayMemory; // capture the day itself
  final DateTime? deletedAt; // trash: null = active; auto-remove after 3 days
  // Optional readable text of a voice note (typed or future on-device STT).
  // Hear first (audio); read second (this). Never required.
  final String? transcript;

  const QuickCapture({
    required this.id,
    required this.at,
    this.text,
    this.audioPath,
    this.linkedRoutineId,
    this.linkedEventId,
    this.tags = const [],
    this.memoryLevel = MemoryLevel.quick,
    this.contextNote,
    this.isDayMemory = false,
    this.deletedAt,
    this.transcript,
  });

  QuickCapture copyWith({
    String? id,
    DateTime? at,
    Object? text = _unset,
    Object? audioPath = _unset,
    Object? linkedRoutineId = _unset,
    Object? linkedEventId = _unset,
    List<String>? tags,
    MemoryLevel? memoryLevel,
    Object? contextNote = _unset,
    bool? isDayMemory,
    Object? deletedAt = _unset,
    Object? transcript = _unset,
  }) {
    return QuickCapture(
      id: id ?? this.id,
      at: at ?? this.at,
      text: text == _unset ? this.text : text as String?,
      audioPath: audioPath == _unset ? this.audioPath : audioPath as String?,
      linkedRoutineId: linkedRoutineId == _unset
          ? this.linkedRoutineId
          : linkedRoutineId as String?,
      linkedEventId: linkedEventId == _unset
          ? this.linkedEventId
          : linkedEventId as String?,
      tags: tags ?? this.tags,
      memoryLevel: memoryLevel ?? this.memoryLevel,
      contextNote:
          contextNote == _unset ? this.contextNote : contextNote as String?,
      isDayMemory: isDayMemory ?? this.isDayMemory,
      deletedAt: deletedAt == _unset ? this.deletedAt : deletedAt as DateTime?,
      transcript:
          transcript == _unset ? this.transcript : transcript as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toIso8601String(),
        'text': text,
        'audioPath': audioPath,
        'linkedRoutineId': linkedRoutineId,
        'linkedEventId': linkedEventId,
        'tags': tags,
        'memoryLevel': memoryLevel.name,
        'contextNote': contextNote,
        'isDayMemory': isDayMemory,
        'deletedAt': deletedAt?.toIso8601String(),
        'transcript': transcript,
      };

  factory QuickCapture.fromJson(Map<String, dynamic> json) => QuickCapture(
        id: json['id'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        text: json['text'] as String?,
        audioPath: json['audioPath'] as String?,
        linkedRoutineId: json['linkedRoutineId'] as String?,
        linkedEventId: json['linkedEventId'] as String?,
        tags: (json['tags'] as List? ?? const []).cast<String>(),
        memoryLevel: MemoryLevel.values.asNameMap()[json['memoryLevel']] ??
            MemoryLevel.quick,
        contextNote: json['contextNote'] as String?,
        isDayMemory: json['isDayMemory'] as bool? ?? false,
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.tryParse(json['deletedAt'] as String),
        transcript: json['transcript'] as String?,
      );
}
