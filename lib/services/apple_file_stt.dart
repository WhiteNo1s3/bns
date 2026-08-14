import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// On-device file ear for Apple (Mac + iPhone).
///
/// After the one mic stops, we read the kept file and write the words
/// into the text box. Hebrew first (`he-IL`). On-device only — the voice
/// never leaves the machine. If the device has no on-device Hebrew,
/// we return empty and the person can type under the labeled take.
class AppleFileStt {
  AppleFileStt._();

  static const _channel = MethodChannel('bns/apple_stt');

  static bool get isSupported => Platform.isMacOS || Platform.isIOS;

  static Future<String> transcribeFile(
    String path, {
    String locale = 'he-IL',
  }) async {
    if (!isSupported || path.isEmpty) return '';
    try {
      final text = await _channel.invokeMethod<String>('transcribeFile', {
        'path': path,
        'locale': locale,
      });
      return (text ?? '').trim();
    } catch (_) {
      return '';
    }
  }
}
