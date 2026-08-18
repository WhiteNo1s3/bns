/// Plain, dependency-free model (no codegen).
library;

const Object _unset = Object();

class TrustedDevice {
  final String id; // deviceId from manifest or generated
  final String name;
  final String lastAddress;
  /// TCP door last heard — same-Mac siblings often sit on 42426+.
  final int lastPort;
  final DateTime lastSyncedAt;
  final String?
      sharedSecret; // base64 AES key for this device (stored locally only)
  final bool autoSyncEnabled;

  /// Per-device LAN sync permission (idea from the 2026-07-05 reference wave).
  /// The device stays trusted/paired, but no LAN transfers happen in either
  /// direction while this is off. Default true — we advise keeping it on for
  /// your own devices; turning it off is a one-tap kill switch, not un-pairing.
  final bool lanSyncAllowed;

  /// This peer wears the HELPER hat (its store says `caregiverDevice`).
  /// Learned from its PULL2 ask and from every store it sends; decides
  /// which care window leaves toward it (the per-level wall, 2026-08-17).
  /// False also covers "not known yet" — an old build that never declared
  /// gets the old behavior until its first store arrives and tells.
  final bool peerIsHelper;

  const TrustedDevice({
    required this.id,
    required this.name,
    required this.lastAddress,
    this.lastPort = 42425,
    required this.lastSyncedAt,
    this.sharedSecret,
    this.autoSyncEnabled = true,
    this.lanSyncAllowed = true,
    this.peerIsHelper = false,
  });

  TrustedDevice copyWith({
    String? id,
    String? name,
    String? lastAddress,
    int? lastPort,
    DateTime? lastSyncedAt,
    Object? sharedSecret = _unset,
    bool? autoSyncEnabled,
    bool? lanSyncAllowed,
    bool? peerIsHelper,
  }) {
    return TrustedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      lastAddress: lastAddress ?? this.lastAddress,
      lastPort: lastPort ?? this.lastPort,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      sharedSecret:
          sharedSecret == _unset ? this.sharedSecret : sharedSecret as String?,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      lanSyncAllowed: lanSyncAllowed ?? this.lanSyncAllowed,
      peerIsHelper: peerIsHelper ?? this.peerIsHelper,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastAddress': lastAddress,
        'lastPort': lastPort,
        'lastSyncedAt': lastSyncedAt.toIso8601String(),
        'sharedSecret': sharedSecret,
        'autoSyncEnabled': autoSyncEnabled,
        'lanSyncAllowed': lanSyncAllowed,
        'peerIsHelper': peerIsHelper,
      };

  factory TrustedDevice.fromJson(Map<String, dynamic> json) => TrustedDevice(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Device',
        lastAddress: json['lastAddress'] as String? ?? '',
        lastPort: (json['lastPort'] as num?)?.toInt() ?? 42425,
        lastSyncedAt:
            DateTime.tryParse(json['lastSyncedAt'] as String? ?? '') ??
                DateTime.now(),
        sharedSecret: json['sharedSecret'] as String?,
        autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
        lanSyncAllowed: json['lanSyncAllowed'] as bool? ?? true,
        peerIsHelper: json['peerIsHelper'] as bool? ?? false,
      );
}
