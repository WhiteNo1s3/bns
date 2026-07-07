import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/sync/sync_progress.dart';
import 'package:bns/core/models/trusted_device.dart';

/// Simple peer representation discovered on LAN.
class BnsPeer {
  final String deviceName;
  final String address;
  final int port;
  final DateTime lastSeen;
  final String? lastExportTime;
  final String deviceId;

  BnsPeer({
    required this.deviceName,
    required this.address,
    required this.port,
    required this.lastSeen,
    this.lastExportTime,
    required this.deviceId,
  });

  @override
  String toString() => '$deviceName ($address)';
}

/// A pairing request from another device, surfaced to the UI.
/// The user types the 6-digit code shown on the OTHER device —
/// the code itself never crosses the network.
class PairingRequest {
  final String deviceId;
  final String deviceName;
  final String address;

  PairingRequest(
      {required this.deviceId,
      required this.deviceName,
      required this.address});
}

/// Secure + progress-aware LAN sync service.
///
/// Security model:
/// - This device has ONE stable deviceId (stored in settings) — trust is bound to it.
/// - Unknown devices must pair: initiator shows a 6-digit code, the user TYPES it
///   on the receiving device. Both sides derive the same AES key from
///   sha256(code + initiatorDeviceId). The code is never transmitted.
/// - All data transfers are AES-CBC with a fresh random IV prepended.
/// - PULL requests only get data encrypted with the requester's shared key —
///   an unknown device gets nothing.
///
/// Wire protocol (TCP, one line header then raw bytes):
///   PAIR <deviceId> <deviceName...>   → receiver prompts for code, replies "OK"/"NO"
///   PUSH <deviceId>                    → header line, then IV+ciphertext of a .bns
///   PULL <deviceId>                    → replies with IV+ciphertext of a .bns
class LanSyncService {
  static const int discoveryPort = 42424;
  static const String magic = 'BNS_HELLO';
  static const int transferPort = 42425;

  final _peers = <String, BnsPeer>{};

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _broadcastTimer;

  final StreamController<List<BnsPeer>> _peersController =
      StreamController.broadcast();
  final StreamController<SyncProgress> _progressController =
      StreamController.broadcast();

  Stream<List<BnsPeer>> get peersStream => _peersController.stream;
  Stream<SyncProgress> get progressStream => _progressController.stream;

  /// Set by the Sync screen: asks the user to type the code shown on the
  /// initiating device. Return null to decline. If nobody is listening
  /// (screen closed), pairing requests are declined — never auto-accepted.
  Future<String?> Function(PairingRequest request)? onPairRequest;

  String? _deviceName;
  String _myDeviceId = '';
  bool _autoSyncEnabled = true;
  final Set<String> _trustedIds = {};
  // Per-device LAN kill switch: paired but LAN-disabled devices sync nothing.
  final Set<String> _lanAllowedIds = {};
  final Set<String> _autoSyncedThisSession = {};

  /// Reload trust + per-device LAN permissions from the store.
  /// Call after pairing, forgetting, or toggling "LAN allowed" in the UI.
  Future<void> refreshTrustPolicy() async {
    final trusted = await IsarService.getTrustedDevices();
    _trustedIds
      ..clear()
      ..addAll(trusted.map((d) => d.id));
    _lanAllowedIds
      ..clear()
      ..addAll(trusted.where((d) => d.lanSyncAllowed).map((d) => d.id));
  }

  bool get isRunning => _udpSocket != null;

  Future<void> start({required String deviceName, bool autoSync = true}) async {
    if (isRunning) return;
    _deviceName = deviceName;
    _autoSyncEnabled = autoSync;

    final settings = await IsarService.getSettings();
    _myDeviceId = settings.deviceId;

    await refreshTrustPolicy();

    _udpSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    _udpSocket!.broadcastEnabled = true;

    _udpSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final d = _udpSocket!.receive();
        if (d != null) _handleDiscovery(d);
      }
    });

    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (isRunning) _broadcastHello();
    });
    await _startTcpServer();
    _broadcastHello();

    _emitProgress(const SyncProgress(
        progress: 0.0, message: 'Looking for your other devices on Wi-Fi...'));
  }

  void _broadcastHello() {
    if (_udpSocket == null || _deviceName == null) return;

    final payload = jsonEncode({
      'magic': magic,
      'deviceName': _deviceName,
      'deviceId': _myDeviceId, // stable — trust depends on it
      'lastExport': DateTime.now().toIso8601String(),
      'port': transferPort,
    });
    _udpSocket!.send(utf8.encode(payload), InternetAddress('255.255.255.255'),
        discoveryPort);
  }

  void _handleDiscovery(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      if (!raw.contains(magic)) return; // fast reject non-BNS traffic
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['magic'] != magic) return;

      final peerId = data['deviceId'] as String? ?? '';
      if (peerId.isEmpty || peerId == _myDeviceId) return;

      final peer = BnsPeer(
        deviceName: data['deviceName'] ?? 'Unknown',
        address: datagram.address.address,
        port: (data['port'] as num?)?.toInt() ?? transferPort,
        lastSeen: DateTime.now(),
        lastExportTime: data['lastExport'],
        deviceId: peerId,
      );

      _peers[peer.deviceId] = peer;
      _peersController.add(_peers.values.toList());

      // Auto-sync trusted AND lan-allowed devices, at most once per session.
      if (_autoSyncEnabled &&
          _trustedIds.contains(peer.deviceId) &&
          _lanAllowedIds.contains(peer.deviceId) &&
          !_autoSyncedThisSession.contains(peer.deviceId)) {
        _autoSyncedThisSession.add(peer.deviceId);
        syncWithPeer(peer, isAuto: true);
      }
    } catch (_) {}
  }

  Future<void> _startTcpServer() async {
    _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, transferPort);
    _tcpServer!.listen((s) => _handleIncoming(s));
  }

  Future<void> _handleIncoming(Socket socket) async {
    try {
      final b = BytesBuilder();
      await for (final c in socket) {
        b.add(c);
        // PAIR/PULL are header-only; handle as soon as the line is complete.
        final bytes = b.toBytes();
        final nl = bytes.indexOf(10); // '\n'
        if (nl != -1) {
          final header = utf8.decode(bytes.sublist(0, nl)).trim();
          if (header.startsWith('PAIR ') || header.startsWith('PULL ')) {
            await _handleHeaderOnly(header, socket);
            return;
          }
          // PUSH: keep reading until the sender closes, then process below.
        }
      }

      final bytes = b.takeBytes();
      final nl = bytes.indexOf(10);
      if (nl == -1) return;
      final header = utf8.decode(bytes.sublist(0, nl)).trim();
      final body = bytes.sublist(nl + 1);

      if (header.startsWith('PUSH ')) {
        await _handlePush(header.substring(5).trim(), body);
      }
    } catch (e) {
      _emitProgress(
          SyncProgress(progress: 0, message: 'Receive problem', error: '$e'));
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> _handleHeaderOnly(String header, Socket socket) async {
    try {
      if (header.startsWith('PAIR ')) {
        final rest = header.substring(5).trim();
        final sp = rest.indexOf(' ');
        final peerId = sp == -1 ? rest : rest.substring(0, sp);
        final peerName = sp == -1 ? 'Device' : rest.substring(sp + 1);

        final handler = onPairRequest;
        if (handler == null) {
          socket.add(utf8.encode('NO\n'));
          return;
        }
        final code = await handler(PairingRequest(
          deviceId: peerId,
          deviceName: peerName,
          address: socket.remoteAddress.address,
        ));
        if (code == null || code.trim().isEmpty) {
          socket.add(utf8.encode('NO\n'));
          return;
        }

        // Same derivation as the initiator: code + initiator's deviceId.
        final key = deriveKey(code.trim(), peerId);
        await IsarService.saveTrustedDevice(TrustedDevice(
          id: peerId,
          name: peerName,
          lastAddress: socket.remoteAddress.address,
          lastSyncedAt: DateTime.now(),
          sharedSecret: key.base64,
          autoSyncEnabled: true,
        ));
        _trustedIds.add(peerId);
        socket.add(utf8.encode('OK\n'));
        _emitProgress(const SyncProgress(
            progress: 1.0,
            message: 'Paired safely. You can sync now.',
            isComplete: true));
      } else if (header.startsWith('PULL ')) {
        final requesterId = header.substring(5).trim();
        final trusted = await IsarService.getTrustedDevice(requesterId);
        if (trusted?.sharedSecret == null || !trusted!.lanSyncAllowed) {
          // Unknown or LAN-disabled device gets nothing. Never plaintext, never data.
          return;
        }
        final f = await BnsExporter.exportFullSnapshot();
        final cipher = _encrypt(await f.readAsBytes(), trusted.sharedSecret!);
        socket.add(cipher);
      }
      await socket.flush();
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  Future<void> _handlePush(String senderId, List<int> body) async {
    final trusted = await IsarService.getTrustedDevice(senderId);
    if (trusted?.sharedSecret == null || !trusted!.lanSyncAllowed) {
      // Unknown sender, or LAN disabled for this device — ignore entirely.
      return;
    }

    _emitProgress(const SyncProgress(
        progress: 0.75, message: 'Receiving your updated information...'));

    final plain = _decrypt(Uint8List.fromList(body), trusted.sharedSecret!);
    // Only a genuine .bns payload is ever accepted — wrong key, truncated
    // data, or a hostile file all fail this structural check and go nowhere.
    BnsImporter.validateBnsBytes(plain);
    final temp = File('${(await getTemporaryDirectory()).path}/lan_recv.bns');
    await temp.writeAsBytes(plain);
    await BnsImporter.importMerge(temp);
    try {
      await temp.delete();
    } catch (_) {}

    await IsarService.updateTrustedDeviceLastSync(
        senderId, trusted.lastAddress);
    _emitProgress(const SyncProgress(
        progress: 1.0,
        message: 'Update complete. All good.',
        isComplete: true));
  }

  // Public API

  Future<void> syncWithPeer(BnsPeer peer, {bool isAuto = false}) async {
    final trusted = await IsarService.getTrustedDevice(peer.deviceId);

    if (trusted?.sharedSecret == null) {
      _emitProgress(const SyncProgress(
          progress: 0.1,
          message: 'New device detected. Pairing with a code is required.'));
      return;
    }
    if (!trusted!.lanSyncAllowed) {
      if (!isAuto) {
        _emitProgress(SyncProgress(
            progress: 0,
            message:
                'LAN transfers are switched off for ${peer.deviceName}. Flip its "LAN allowed" toggle to sync.'));
      }
      return;
    }

    try {
      _emitProgress(const SyncProgress(
          progress: 0.15,
          message: 'Creating a full picture of your current data...'));

      final bns = await BnsExporter.exportFullSnapshot();
      final plain = await bns.readAsBytes();

      _emitProgress(const SyncProgress(
          progress: 0.4, message: 'Locking it safely for transfer...'));

      final cipher = _encrypt(plain, trusted.sharedSecret!);

      _emitProgress(SyncProgress(
          progress: 0.6, message: 'Sending to ${peer.deviceName}...'));

      final s = await Socket.connect(peer.address, peer.port);
      s.add(utf8.encode('PUSH $_myDeviceId\n'));
      s.add(cipher);
      await s.flush();
      await s.close();

      _emitProgress(const SyncProgress(
          progress: 0.8,
          message: 'Getting the latest from the other device...'));

      await _pullTrusted(peer, trusted.sharedSecret!);

      await IsarService.updateTrustedDeviceLastSync(
          peer.deviceId, peer.address);

      _emitProgress(const SyncProgress(
        progress: 1.0,
        message: 'Everything is in sync across your devices. Nice work.',
        isComplete: true,
      ));
    } catch (e) {
      _emitProgress(SyncProgress(
          progress: 0, message: 'Sync paused', error: e.toString()));
    }
  }

  Future<void> _pullTrusted(BnsPeer peer, String secret) async {
    final s = await Socket.connect(peer.address, peer.port);
    s.add(utf8.encode('PULL $_myDeviceId\n'));
    await s.flush();

    final b = BytesBuilder();
    await for (final c in s) {
      b.add(c);
    }
    await s.close();

    final encBytes = b.takeBytes();
    if (encBytes.isEmpty) return;

    final plain = _decrypt(Uint8List.fromList(encBytes), secret);
    BnsImporter.validateBnsBytes(plain); // .bns payloads only, ever
    final f = File('${(await getTemporaryDirectory()).path}/pull.bns');
    await f.writeAsBytes(plain);
    await BnsImporter.importMerge(f);
    try {
      await f.delete();
    } catch (_) {}
  }

  // === SECURE PAIRING ===
  // Initiator: shows a code + sends "PAIR" with its id/name. The other user
  // TYPES the code there. Both derive the same key; nothing secret on the wire.

  String generatePairingCode() =>
      List.generate(6, (_) => Random.secure().nextInt(10)).join();

  Future<bool> completePairing(BnsPeer peer, String code) async {
    try {
      _emitProgress(const SyncProgress(
          progress: 0.25,
          message: 'Waiting for the other device to enter the code...'));

      final s = await Socket.connect(peer.address, peer.port);
      s.add(utf8.encode('PAIR $_myDeviceId ${_deviceName ?? 'BNS Device'}\n'));
      await s.flush();

      final reply = utf8
          .decode(
            await s
                .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk)),
          )
          .trim();
      await s.close();

      if (reply != 'OK') {
        _emitProgress(const SyncProgress(
            progress: 0,
            message:
                'The other device declined (or the screen was closed there).'));
        return false;
      }

      final key = deriveKey(code, _myDeviceId);
      await IsarService.saveTrustedDevice(TrustedDevice(
        id: peer.deviceId,
        name: peer.deviceName,
        lastAddress: peer.address,
        lastSyncedAt: DateTime.now(),
        sharedSecret: key.base64,
        autoSyncEnabled: true,
      ));
      _trustedIds.add(peer.deviceId);

      _emitProgress(const SyncProgress(
          progress: 0.9, message: 'Paired safely. Syncing now...'));

      await syncWithPeer(peer);
      return true;
    } catch (e) {
      _emitProgress(SyncProgress(
          progress: 0,
          message: 'Pairing could not be completed',
          error: e.toString()));
      return false;
    }
  }

  /// Shared derivation for both sides: sha256(code + initiator deviceId).
  static enc.Key deriveKey(String code, String initiatorDeviceId) {
    final d = sha256.convert(utf8.encode(code + initiatorDeviceId));
    return enc.Key(Uint8List.fromList(d.bytes.sublist(0, 32)));
  }

  Uint8List _encrypt(List<int> data, String secret) {
    final k = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = e.encryptBytes(data, iv: iv);
    return Uint8List.fromList(iv.bytes + encrypted.bytes);
  }

  /// Counterpart of [_encrypt]: first 16 bytes are the IV.
  List<int> _decrypt(Uint8List data, String secret) {
    if (data.length <= 16) return const [];
    final k = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc));
    final iv = enc.IV(Uint8List.fromList(data.sublist(0, 16)));
    return e.decryptBytes(enc.Encrypted(Uint8List.fromList(data.sublist(16))),
        iv: iv);
  }

  // Helpers

  Future<List<TrustedDevice>> getTrustedDevices() =>
      IsarService.getTrustedDevices();

  Future<void> forgetDevice(String id) async {
    await IsarService.removeTrustedDevice(id);
    _trustedIds.remove(id);
  }

  void setAutoSync(bool v) => _autoSyncEnabled = v;

  Future<File> manualExport() => BnsExporter.exportFullSnapshot();

  Future<void> manualImport(File f, {bool replace = false}) async {
    await (replace ? BnsImporter.importReplace(f) : BnsImporter.importMerge(f));
  }

  void _emitProgress(SyncProgress p) => _progressController.add(p);

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _tcpServer?.close();
    _tcpServer = null;
    _peers.clear();
    if (!_peersController.isClosed) _peersController.add([]);
  }

  void dispose() {
    stop();
    _peersController.close();
    _progressController.close();
  }
}
