import 'dart:io';

/// MVP LAN discovery using UDP broadcast.
/// Broadcasts "BNS_HELLO" + device info.
/// Listens for peers on the same subnet.
/// Zero configuration. All local.
class LanDiscovery {
  static const int port = 42424;
  static const String magic = 'BNS_HELLO';

  // TODO: implement with RawDatagramSocket
  // - start() listens and broadcasts periodically
  // - onPeerFound callback with name + address + lastSync
  // - stop()

  Future<void> start({required String deviceName}) async {
    // Placeholder
    print('LAN discovery would start on UDP $port for $deviceName');
  }

  void stop() {}
}
