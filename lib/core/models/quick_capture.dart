import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'quick_capture.freezed.dart';
part 'quick_capture.g.dart';

@freezed
@Collection()
class QuickCapture with _$QuickCapture {
  const QuickCapture._();

  const factory QuickCapture({
    @Index(unique: true) required String id,
    required DateTime at,
    String? text,
    String? audioPath, // relative inside .bns or absolute in app docs after import
    String? linkedRoutineId,
    String? linkedEventId,
    @Default([]) List<String> tags,
  }) = _QuickCapture;

  factory QuickCapture.fromJson(Map<String, dynamic> json) =>
      _$QuickCaptureFromJson(json);
}
