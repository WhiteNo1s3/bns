import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:isar/isar.dart';

part 'trusted_device.freezed.dart';
part 'trusted_device.g.dart';

@freezed
@Collection()
class TrustedDevice with _$TrustedDevice {
  const TrustedDevice._();

  const factory TrustedDevice({
    @Index(unique: true) required String id,           // deviceId from manifest or generated
    required String name,
    required String lastAddress,
    required DateTime lastSyncedAt,
    String? sharedSecret,   // base64 encoded AES key for this device (stored locally only)
    @Default(true) bool autoSyncEnabled,
  }) = _TrustedDevice;

  factory TrustedDevice.fromJson(Map<String, dynamic> json) =>
      _$TrustedDeviceFromJson(json);
}
