/// Plain, dependency-free model (no codegen).
library;

const Object _unset = Object();

class TrustedDevice {
  final String id; // deviceId from manifest or generated
  final String name;
  final String lastAddress;
  final DateTime lastSyncedAt;
  final String?
      sharedSecret; // base64 AES key for this device (stored locally only)
  final bool autoSyncEnabled;

  /// Per-device LAN sync permission (idea from the 2026-07-05 reference wave).
  /// The device stays trusted/paired, but no LAN transfers happen in either
  /// direction while this is off. Default true — we advise keeping it on for
  /// your own devices; turning it off is a one-tap kill switch, not un-pairing.
  final bool lanSyncAllowed;

  const TrustedDevice({
    required this.id,
    required this.name,
    required this.lastAddress,
    required this.lastSyncedAt,
    this.sharedSecret,
    this.autoSyncEnabled = true,
    this.lanSyncAllowed = true,
  });

  TrustedDevice copyWith({
    String? id,
    String? name,
    String? lastAddress,
    DateTime? lastSyncedAt,
    Object? sharedSecret = _unset,
    bool? autoSyncEnabled,
    bool? lanSyncAllowed,
  }) {
    return TrustedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      lastAddress: lastAddress ?? this.lastAddress,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      sharedSecret:
          sharedSecret == _unset ? this.sharedSecret : sharedSecret as String?,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lanSyncAllowed: lanSyncAllowed ?? this.lanSyncAllowed,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastAddress': lastAddress,
        'lastSyncedAt': lastSyncedAt.toIso8601String(),
        'sharedSecret': sharedSecret,
        'autoSyncEnabled': autoSyncEnabled,
        'lanSyncAllowed': lanSyncAllowed,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Device',
        lastAddress: json['lastAddress'] as String? ?? '',
        lastSyncedAt:
            DateTime.tryParse(json['lastSyncedAt'] as String? ?? '') ??
                DateTime.now(),
        sharedSecret: json['sharedSecret'] as String?,
        autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
        lanSyncAllowed: json['lanSyncAllowed'] as bool? ?? true,
      );
}
