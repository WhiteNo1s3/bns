import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

enum ThemeModeSetting { system, light, dark }

enum RelaxingPalette { teal, lavender, sand, deep }

@freezed
@Collection()
class AppSettings with _$AppSettings {
  const AppSettings._();

  const factory AppSettings({
    @Index(unique: true) @Default('singleton') String id,
    @Default('My BNS Device') String deviceName,
    @Default(ThemeModeSetting.system) ThemeModeSetting themeMode,
    @Default(RelaxingPalette.teal) RelaxingPalette relaxingPalette,
    @Default(true) bool notificationsEnabled,
    @Default(true) bool hapticsEnabled,
    DateTime? lastFullSyncAt,
    // Retention for historical data to keep .bns files small and sync fast.
    // Default 14 days (2 weeks rolling window).
    // Old past data (completions, captures, old past events) is auto-pruned.
    // Future calendar events are kept indefinitely for long-term planning (even 10000 years).
    // Set to 0 for unlimited (allows huge/redundant files if user wants).
    // User can expand but warned about slower sync.
    @Default(14) int retentionDays,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
}
