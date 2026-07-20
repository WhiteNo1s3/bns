/// Plain, dependency-free model (no codegen).
library;

enum ThemeModeSetting { system, light, dark }

enum RelaxingPalette { teal, lavender, sand, deep }

const Object _unset = Object();

class AppSettings {
  final String id;
  final String deviceName;

  /// Stable identity of THIS device for LAN sync trust matching.
  /// Generated once on first run and kept forever (fixes: a random id per
  /// broadcast makes trusted-device matching impossible).
  final String deviceId;

  final ThemeModeSetting themeMode;
  final RelaxingPalette relaxingPalette;
  final bool notificationsEnabled;
  final bool hapticsEnabled;
  final DateTime? lastFullSyncAt;

  // Retention for historical data to keep .bns files small and sync fast.
  // Default 14 days (2 weeks rolling window). 0 = unlimited.
  // Future calendar events are kept indefinitely for long-term planning.
  final int retentionDays;

  // User type for UI adaptation (brighter for fog, simpler for kids, etc.)
  final String userType;

  // How many days forward to show in widget/calendar summary. Default 2.
  final int widgetForwardDays;

  // Quiet mode: reduce animations, confetti, sounds for low-stimulation days.
  final bool quietMode;

  // Seamless imaging: keep BNS_Latest_<device>.bns silently fresh on
  // background/exit so a shareable database file always exists without the
  // user ever exporting. Default true (idea: 2026-07-05 reference wave).
  final bool autoImageEnabled;

  // PC / Desktop keybinds: id -> combo string e.g. "ctrl+enter".
  // Separate enabled map so user can tick/untick without losing the binding.
  // These live in the shared .bns.
  final Map<String, String> keybinds;
  final Map<String, bool> enabledKeybinds;

  // "I am mad" mode — a pressure valve for rage days.
  // Null = calm. Set to now+24h on activation; auto-clears after expiry.
  // Vents captured while active burn out (auto-delete) within ~2 days.
  final DateTime? madModeUntil;

  // The name PEOPLE see when this device shares — a chosen, family-facing
  // name ("Dad", "Yossi"), not the phone's technical name. Shown during
  // pairing acceptance so a trusted person instantly recognizes who is
  // asking. Empty = fall back to deviceName.
  final String shareName;

  // How Today lists the day: 'timeline' (morning→night, default) or
  // 'next' (closest upcoming task from right now first).
  final String todayOrder;

  // GUIDED MODE — "level 4" (owner design, 2026-07-08).
  final bool guidedMode;

  // FULL CARE MODE — the last resort (owner design, 2026-07-06).
  final bool fullCareMode;

  // Rediscovery (owner, 2026-07-20): when the person last opened the app.
  // Used for a calm "your day is here" after a long gap — never guilt.
  final DateTime? lastOpenedAt;

  // First-run list tutorial (tap / long-press / something different).
  final bool hasSeenListTutorial;

  // Fog-first reading: bigger type, simpler surfaces (owner, 2026-07-20).
  final bool fogReading;

  // Soft daily "your list is ready" presence (folder on the desk).
  final bool listReadyNudgeEnabled;

  // CANCELLED server fields — inert compatibility only.
  final String? serverUrl;
  final String? serverToken;

  const AppSettings({
    this.id = 'singleton',
    this.deviceName = 'My BNS Device',
    this.deviceId = '',
    this.themeMode = ThemeModeSetting.system,
    this.relaxingPalette = RelaxingPalette.teal,
    this.notificationsEnabled = true,
    this.hapticsEnabled = true,
    this.lastFullSyncAt,
    this.retentionDays = 20,
    this.userType = 'normal',
    this.widgetForwardDays = 2,
    this.quietMode = false,
    this.autoImageEnabled = true,
    this.keybinds = const {},
    this.enabledKeybinds = const {},
    this.madModeUntil,
    this.shareName = '',
    this.todayOrder = 'timeline',
    this.guidedMode = false,
    this.fullCareMode = false,
    this.lastOpenedAt,
    this.hasSeenListTutorial = false,
    this.fogReading = false,
    this.listReadyNudgeEnabled = true,
    this.serverUrl,
    this.serverToken,
  });

  /// What other people's screens show for this device.
  String get effectiveShareName =>
      shareName.trim().isEmpty ? deviceName : shareName.trim();

  /// Days since last open (null if never recorded).
  int? get daysSinceLastOpen {
    final last = lastOpenedAt;
    if (last == null) return null;
    final a = DateTime(last.year, last.month, last.day);
    final n = DateTime.now();
    final b = DateTime(n.year, n.month, n.day);
    return b.difference(a).inDays;
  }

  AppSettings copyWith({
    String? id,
    String? deviceName,
    String? deviceId,
    ThemeModeSetting? themeMode,
    RelaxingPalette? relaxingPalette,
    bool? notificationsEnabled,
    bool? hapticsEnabled,
    Object? lastFullSyncAt = _unset,
    int? retentionDays,
    String? userType,
    int? widgetForwardDays,
    bool? quietMode,
    bool? autoImageEnabled,
    Map<String, String>? keybinds,
    Map<String, bool>? enabledKeybinds,
    Object? madModeUntil = _unset,
    String? shareName,
    String? todayOrder,
    bool? guidedMode,
    bool? fullCareMode,
    Object? lastOpenedAt = _unset,
    bool? hasSeenListTutorial,
    bool? fogReading,
    bool? listReadyNudgeEnabled,
    Object? serverUrl = _unset,
    Object? serverToken = _unset,
  }) {
    return AppSettings(
      id: id ?? this.id,
      deviceName: deviceName ?? this.deviceName,
      deviceId: deviceId ?? this.deviceId,
      themeMode: themeMode ?? this.themeMode,
      relaxingPalette: relaxingPalette ?? this.relaxingPalette,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      lastFullSyncAt: lastFullSyncAt == _unset
          ? this.lastFullSyncAt
          : lastFullSyncAt as DateTime?,
      retentionDays: retentionDays ?? this.retentionDays,
      userType: userType ?? this.userType,
      widgetForwardDays: widgetForwardDays ?? this.widgetForwardDays,
      quietMode: quietMode ?? this.quietMode,
      autoImageEnabled: autoImageEnabled ?? this.autoImageEnabled,
      keybinds: keybinds ?? this.keybinds,
      enabledKeybinds: enabledKeybinds ?? this.enabledKeybinds,
      madModeUntil: madModeUntil == _unset
          ? this.madModeUntil
          : madModeUntil as DateTime?,
      shareName: shareName ?? this.shareName,
      todayOrder: todayOrder ?? this.todayOrder,
      guidedMode: guidedMode ?? this.guidedMode,
      fullCareMode: fullCareMode ?? this.fullCareMode,
      lastOpenedAt: lastOpenedAt == _unset
          ? this.lastOpenedAt
          : lastOpenedAt as DateTime?,
      hasSeenListTutorial: hasSeenListTutorial ?? this.hasSeenListTutorial,
      fogReading: fogReading ?? this.fogReading,
      listReadyNudgeEnabled:
          listReadyNudgeEnabled ?? this.listReadyNudgeEnabled,
      serverUrl: serverUrl == _unset ? this.serverUrl : serverUrl as String?,
      serverToken:
          serverToken == _unset ? this.serverToken : serverToken as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceName': deviceName,
        'deviceId': deviceId,
        'themeMode': themeMode.name,
        'relaxingPalette': relaxingPalette.name,
        'notificationsEnabled': notificationsEnabled,
        'hapticsEnabled': hapticsEnabled,
        'lastFullSyncAt': lastFullSyncAt?.toIso8601String(),
        'retentionDays': retentionDays,
        'userType': userType,
        'widgetForwardDays': widgetForwardDays,
        'quietMode': quietMode,
        'autoImageEnabled': autoImageEnabled,
        'keybinds': keybinds,
        'enabledKeybinds': enabledKeybinds,
        'madModeUntil': madModeUntil?.toIso8601String(),
        'shareName': shareName,
        'todayOrder': todayOrder,
        'guidedMode': guidedMode,
        'fullCareMode': fullCareMode,
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'hasSeenListTutorial': hasSeenListTutorial,
        'fogReading': fogReading,
        'listReadyNudgeEnabled': listReadyNudgeEnabled,
        'serverUrl': serverUrl,
        'serverToken': serverToken,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        id: json['id'] as String? ?? 'singleton',
        deviceName: json['deviceName'] as String? ?? 'My BNS Device',
        deviceId: json['deviceId'] as String? ?? '',
        themeMode: ThemeModeSetting.values.asNameMap()[json['themeMode']] ??
            ThemeModeSetting.system,
        relaxingPalette:
            RelaxingPalette.values.asNameMap()[json['relaxingPalette']] ??
                RelaxingPalette.teal,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
        lastFullSyncAt: json['lastFullSyncAt'] == null
            ? null
            : DateTime.tryParse(json['lastFullSyncAt'] as String),
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 20,
        userType: json['userType'] as String? ?? 'normal',
        widgetForwardDays: (json['widgetForwardDays'] as num?)?.toInt() ?? 2,
        quietMode: json['quietMode'] as bool? ?? false,
        autoImageEnabled: json['autoImageEnabled'] as bool? ?? true,
        keybinds: (json['keybinds'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        enabledKeybinds: (json['enabledKeybinds'] as Map? ?? const {})
            .map((k, v) => MapEntry(k.toString(), v == true)),
        madModeUntil: json['madModeUntil'] == null
            ? null
            : DateTime.tryParse(json['madModeUntil'] as String),
        shareName: json['shareName'] as String? ?? '',
        todayOrder: json['todayOrder'] as String? ?? 'timeline',
        guidedMode: json['guidedMode'] as bool? ?? false,
        fullCareMode: json['fullCareMode'] as bool? ?? false,
        lastOpenedAt: json['lastOpenedAt'] == null
            ? null
            : DateTime.tryParse(json['lastOpenedAt'] as String),
        hasSeenListTutorial: json['hasSeenListTutorial'] as bool? ?? false,
        fogReading: json['fogReading'] as bool? ?? false,
        listReadyNudgeEnabled: json['listReadyNudgeEnabled'] as bool? ?? true,
        serverUrl: json['serverUrl'] as String?,
        serverToken: json['serverToken'] as String?,
      );
}
