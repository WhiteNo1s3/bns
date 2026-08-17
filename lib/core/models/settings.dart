/// Plain, dependency-free model (no codegen).
library;

enum ThemeModeSetting { system, light, dark }

// Warm family only — green and blue made the owner sick (2026-08-16).
// Old stored names ('teal', 'deep') miss the map and fall back to clay.
enum RelaxingPalette { clay, lavender, sand, rose }

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

  // How loudly a reminder arrives — the person chooses (level 1-2 wave,
  // 2026-08-08). 'quiet' = sits in the shade, no sound; 'gentle' = a normal
  // notification with the soft default chime (the default — a reminder
  // nobody ever sees helps nobody); 'bright' = banner on top of the screen,
  // for the days when the shade might as well not exist.
  final String reminderStyle;

  // The color of reminders, by the like of the user: 'auto' follows the
  // app's own palette; otherwise a gentle named color (teal, lavender,
  // green, amber, rose, sky). Android paints the notification accent with
  // it; the PC in-app reminder card wears it too.
  final String notificationColor;

  // Plans (calendar events with a time) get a heads-up this many minutes
  // before. 0 = right at the time, -1 = no plan reminders. Default 30 —
  // enough time to get ready without living in the future.
  final int eventReminderMinutes;

  // How long an untouched reminder stays in the shade before it quietly
  // leaves (minutes; 0 = stays until seen). Waking at 15:30 to the whole
  // morning stacked up "ruins the flow" (owner QA, 2026-08-14) — stale
  // nudges bow out by themselves; the day inside the app carries the plan.
  final int reminderTimeoutMinutes;

  // OWL TIME (owner, 2026-08-10: "my day isn't done in 00:00"): the hour
  // the person's day actually ends. 0 = midnight (the old world); an owl
  // picks e.g. 4 and everything until 04:00 still belongs to tonight —
  // pills at 02:00 sit at the END of today's list and the day flips while
  // they sleep. Clamped to 0..6 (lib/core/owl_time.dart).
  final int dayRolloverHour;

  // When THIS person's 24-hour day entity begins (0 = midnight, the old
  // world). Ben wakes at 15:00 and the day runs 15:00 → 05:00. Same clock
  // as [dayRolloverHour] — later-today, the list, Next, and reminders
  // all read this pair. Clamped to 0..23.
  final int dayStartHour;

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

  // "STT all the time" (owner, 2026-07-26; comments pass same day): dictation
  // mics on every person-facing comment field (diary, skip-reason, capture);
  // after a phone voice note, optional speak-words once the mic is free.
  // Never concurrent STT+record on Android. Free, on-device, no cloud accounts.
  // Default ON; devices without an engine degrade silently to voice+typing.
  final bool sttEnabled;

  // Speech recognition language, e.g. 'he-IL' or 'en-US'.
  // Empty = the device's own language (the right default for almost everyone).
  final String sttLocale;

  // The app's language: 'he' (Hebrew, RTL — the default; the first users
  // are Israeli, the TBI community QA'ing production) or 'en' (English).
  final String appLanguage;

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

  // CARE LEVEL — the whole care spectrum as ONE visible choice (1..4):
  //   1 Independent — nothing leaves the device unless chosen.
  //   2 Family knows the important things — chosen plans in the family file.
  //   3 Full care — the people who care see everything (fullCareMode).
  //   4 Guided — only the list; the caregiver builds the day (guidedMode,
  //     which also implies fullCareMode).
  // The level is the story; guidedMode/fullCareMode stay the source of
  // truth for behavior and are kept coherent by the selector.
  final int careLevel;

  // THE CAREGIVER'S KEY (owner decision, 2026-08-15): a salted hash of the
  // password set together when raising to level 3–4. Lowering the level —
  // and the caregiver door in guided mode — opens with it, so one confused
  // tap cannot dissolve the arrangement that lets the caregiver NOT hover.
  // Empty = no lock (every pre-lock device). Only the hash ever exists.
  final String careLockHash;

  // CAREGIVER DEVICE — this copy belongs to the person who HELPS, not the
  // person being helped (owner, 2026-07-27). It changes what this device
  // is for: building the other person's day, seeing what they told, and
  // never nagging its holder about routines that are not theirs.
  //
  // It is a property of the DEVICE, not of the patient — and it is never
  // announced on the patient's screen. Being helped in the shower already
  // costs privacy; the app must not add a badge that says "you are
  // watched" to a person who may be paranoid and right to be.
  final bool caregiverDevice;

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
    this.relaxingPalette = RelaxingPalette.clay,
    this.notificationsEnabled = true,
    this.reminderStyle = 'gentle',
    this.dayRolloverHour = 0,
    this.dayStartHour = 0,
    this.notificationColor = 'auto',
    this.eventReminderMinutes = 30,
    this.reminderTimeoutMinutes = 120,
    this.hapticsEnabled = true,
    this.lastFullSyncAt,
    // Owner FINAL (2026-07-08): 20 days of history, +10 forward on calendar.
    this.retentionDays = 20,
    this.userType = 'normal',
    this.widgetForwardDays = 2,
    this.quietMode = false,
    this.sttEnabled = true,
    this.sttLocale = '',
    this.appLanguage = 'he',
    this.autoImageEnabled = true,
    this.keybinds = const {},
    this.enabledKeybinds = const {},
    this.madModeUntil,
    this.shareName = '',
    this.todayOrder = 'timeline',
    this.guidedMode = false,
    this.fullCareMode = false,
    this.careLevel = 1,
    this.careLockHash = '',
    this.caregiverDevice = false,
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
    String? reminderStyle,
    int? dayRolloverHour,
    int? dayStartHour,
    String? notificationColor,
    int? eventReminderMinutes,
    int? reminderTimeoutMinutes,
    bool? hapticsEnabled,
    Object? lastFullSyncAt = _unset,
    int? retentionDays,
    String? userType,
    int? widgetForwardDays,
    bool? quietMode,
    bool? sttEnabled,
    String? sttLocale,
    String? appLanguage,
    bool? autoImageEnabled,
    Map<String, String>? keybinds,
    Map<String, bool>? enabledKeybinds,
    Object? madModeUntil = _unset,
    String? shareName,
    String? todayOrder,
    bool? guidedMode,
    bool? fullCareMode,
    int? careLevel,
    String? careLockHash,
    bool? caregiverDevice,
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
      reminderStyle: reminderStyle ?? this.reminderStyle,
      dayRolloverHour: dayRolloverHour ?? this.dayRolloverHour,
      dayStartHour: dayStartHour ?? this.dayStartHour,
      notificationColor: notificationColor ?? this.notificationColor,
      eventReminderMinutes: eventReminderMinutes ?? this.eventReminderMinutes,
      reminderTimeoutMinutes:
          reminderTimeoutMinutes ?? this.reminderTimeoutMinutes,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      lastFullSyncAt: lastFullSyncAt == _unset
          ? this.lastFullSyncAt
          : lastFullSyncAt as DateTime?,
      retentionDays: retentionDays ?? this.retentionDays,
      userType: userType ?? this.userType,
      widgetForwardDays: widgetForwardDays ?? this.widgetForwardDays,
      quietMode: quietMode ?? this.quietMode,
      sttEnabled: sttEnabled ?? this.sttEnabled,
      sttLocale: sttLocale ?? this.sttLocale,
      appLanguage: appLanguage ?? this.appLanguage,
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
      careLevel: careLevel ?? this.careLevel,
      careLockHash: careLockHash ?? this.careLockHash,
      caregiverDevice: caregiverDevice ?? this.caregiverDevice,
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
        'reminderStyle': reminderStyle,
        'dayRolloverHour': dayRolloverHour,
        'dayStartHour': dayStartHour,
        'notificationColor': notificationColor,
        'eventReminderMinutes': eventReminderMinutes,
        'reminderTimeoutMinutes': reminderTimeoutMinutes,
        'hapticsEnabled': hapticsEnabled,
        'lastFullSyncAt': lastFullSyncAt?.toIso8601String(),
        'retentionDays': retentionDays,
        'userType': userType,
        'widgetForwardDays': widgetForwardDays,
        'quietMode': quietMode,
        'sttEnabled': sttEnabled,
        'sttLocale': sttLocale,
        'appLanguage': appLanguage,
        'autoImageEnabled': autoImageEnabled,
        'keybinds': keybinds,
        'enabledKeybinds': enabledKeybinds,
        'madModeUntil': madModeUntil?.toIso8601String(),
        'shareName': shareName,
        'todayOrder': todayOrder,
        'guidedMode': guidedMode,
        'fullCareMode': fullCareMode,
        'careLevel': careLevel,
        'careLockHash': careLockHash,
        'caregiverDevice': caregiverDevice,
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
                RelaxingPalette.clay,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        reminderStyle: json['reminderStyle'] as String? ?? 'gentle',
        dayRolloverHour: _hourFromJson(json['dayRolloverHour'], 6),
        dayStartHour: _hourFromJson(json['dayStartHour'], 23),
        notificationColor: json['notificationColor'] as String? ?? 'auto',
        eventReminderMinutes:
            (json['eventReminderMinutes'] as num?)?.toInt() ?? 30,
        reminderTimeoutMinutes:
            (json['reminderTimeoutMinutes'] as num?)?.toInt() ?? 120,
        hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
        lastFullSyncAt: json['lastFullSyncAt'] == null
            ? null
            : DateTime.tryParse(json['lastFullSyncAt'] as String),
        retentionDays: (json['retentionDays'] as num?)?.toInt() ?? 20,
        userType: json['userType'] as String? ?? 'normal',
        widgetForwardDays: (json['widgetForwardDays'] as num?)?.toInt() ?? 2,
        quietMode: json['quietMode'] as bool? ?? false,
        sttEnabled: json['sttEnabled'] as bool? ?? true,
        sttLocale: json['sttLocale'] as String? ?? '',
        appLanguage: json['appLanguage'] as String? ?? 'he',
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
        // Migration for existing users (pre-careLevel): derive the level
        // from the flags they already live with.
        careLevel: (json['careLevel'] as num?)?.toInt() ??
            (json['guidedMode'] == true
                ? 4
                : (json['fullCareMode'] == true ? 3 : 1)),
        careLockHash: json['careLockHash'] as String? ?? '',
        caregiverDevice: json['caregiverDevice'] as bool? ?? false,
        serverUrl: json['serverUrl'] as String?,
        serverToken: json['serverToken'] as String?,
      );
}

int _hourFromJson(Object? value, int max) {
  final n = value is num
      ? value.toInt()
      : value is String
          ? int.tryParse(value)
          : null;
  final h = n ?? 0;
  return h < 0 ? 0 : (h > max ? max : h);
}
