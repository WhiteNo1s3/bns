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

  // GUIDED MODE — "level 4" (owner design, 2026-07-08, from a Holocaust
  // survivor's kid with Alzheimer's: "when it kills the brain only routines
  // work"). The person gets ONLY the list — big, visual, accessible. They
  // can tick a task (with their acceptance) and long-press to tell about a
  // problem; everything else is built by the INSPECTOR (the caregiver, via
  // their paired device). No editing, no building a day — instructions,
  // not choices. Enabling guided mode also enables full care.
  final bool guidedMode;

  // FULL CARE MODE — the last resort, by owner design (2026-07-06), for the
  // severely impaired ("people who had their name and number on their back
  // in rehabilitation"). When ON, the family file contains EVERYTHING —
  // every fleeting thought is gold for the people easing their path
  // ("he thought about shaving but doesn't shave"; "super annoyed at the
  // elevator" → assist with elevators). Default OFF; enabling is guarded
  // behind a typed confirmation; turning it off is always one tap.
  final bool fullCareMode;

  // CANCELLED feature (owner decision 2026-07-06): the 0.12a account-server
  // pivot. The client/server code is quarantined in prototypes/cloud-pivot/
  // and is NOT in any build. These two fields stay only as inert
  // compatibility placeholders (normally null); nothing in lib/ makes
  // network use of them. serverToken is still stripped from every .bns
  // export defensively (see BnsExporter).
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
    // Owner FINAL (2026-07-08): 20 days of history, +10 forward on calendar.
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
    this.serverUrl,
    this.serverToken,
  });

  /// What other people's screens show for this device.
  String get effectiveShareName =>
      shareName.trim().isEmpty ? deviceName : shareName.trim();

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
        serverUrl: json['serverUrl'] as String?,
        serverToken: json['serverToken'] as String?,
      );
}
