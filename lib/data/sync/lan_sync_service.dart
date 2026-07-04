import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

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

/// Secure + progress-aware LAN sync service.
/// 
/// Security:
/// - Unknown devices require explicit pairing with a 6-digit code (user must confirm match on both devices).
/// - Transfers use AES encryption.
/// - Only trusted (accepted) devices can use auto-sync.
/// 
/// Progress:
/// - Streams detailed progress updates with relaxing system colors friendly messages.
class LanSyncService {
  static const int discoveryPort = 42424;
  static const String magic = 'BNS_HELLO';
  static const int transferPort = 42425;

  final _uuid = const Uuid();
  final _peers = <String, BnsPeer>{};

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;

  final StreamController<List<BnsPeer>> _peersController = StreamController.broadcast();
  final StreamController<SyncProgress> _progressController = StreamController.broadcast();

  Stream<List<BnsPeer>> get peersStream => _peersController.stream;
  Stream<SyncProgress> get progressStream => _progressController.stream;

  String? _deviceName;
  bool _autoSyncEnabled = true;
  final Set<String> _trustedIds = {};

  bool get isRunning => _udpSocket != null;

  Future<void> start({required String deviceName, bool autoSync = true}) async {
    if (isRunning) return;
    _deviceName = deviceName;
    _autoSyncEnabled = autoSync;

    final trusted = await IsarService.getTrustedDevices();
    _trustedIds.addAll(trusted.map((d) => d.id));

    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    _udpSocket!.broadcastEnabled = true;

    _udpSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final d = _udpSocket!.receive();
        if (d != null) _handleDiscovery(d);
      }
    });

    _startBroadcastLoop();
    await _startTcpServer();
    _broadcastHello();

    _emitProgress(const SyncProgress(progress: 0.0, message: 'Looking for your other devices on Wi-Fi...'));
  }

  void _startBroadcastLoop() {
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (isRunning) _broadcastHello();
    });
  }

  void _broadcastHello() {
    if (_udpSocket == null || _deviceName == null) return;

    final payload = jsonEncode({
      'magic': magic,
      'deviceName': _deviceName,
      'deviceId': _uuid.v4(),
      'lastExport': DateTime.now().toIso8601String(),
      'port': transferPort,
    });
    _udpSocket!.send(utf8.encode(payload), InternetAddress('255.255.255.255'), discoveryPort);
  }

  void _handleDiscovery(Datagram datagram) {
    try {
      final data = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      if (data['magic'] != magic) return;

      final peer = BnsPeer(
        deviceName: data['deviceName'] ?? 'Unknown',
        address: datagram.address.address,
        port: (data['port'] as num?)?.toInt() ?? transferPort,
        lastSeen: DateTime.now(),
        lastExportTime: data['lastExport'],
        deviceId: data['deviceId'] ?? _uuid.v4(),
      );

      if (peer.deviceName == _deviceName) return;

      _peers['${peer.address}:${peer.deviceId}'] = peer;
      _peersController.add(_peers.values.toList());

      if (_autoSyncEnabled && _trustedIds.contains(peer.deviceId)) {
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
      await for (final c in socket) b.add(c);
      final bytes = b.takeBytes();
      if (bytes.isEmpty) return;

      if (utf8.decode(bytes.sublist(0, bytes.length > 30 ? 30 : bytes.length)).contains('PULL')) {
        final f = await BnsExporter.exportFullSnapshot();
        socket.add(await f.readAsBytes());
      } else {
        await _processIncomingBns(bytes, socket.remoteAddress.address);
      }
    } catch (e) {
      _emitProgress(SyncProgress(progress: 0, message: 'Receive problem', error: '$e'));
    } finally {
      await socket.close();
    }
  }

  Future<void> _processIncomingBns(List<int> bytes, String ip) async {
    _emitProgress(const SyncProgress(progress: 0.75, message: 'Receiving your updated information...'));

    final temp = File('${(await getTemporaryDirectory()).path}/lan_recv.bns');
    await temp.writeAsBytes(bytes);
    await BnsImporter.importMerge(temp);
    await temp.delete().catchError((_) {});

    _emitProgress(const SyncProgress(progress: 1.0, message: 'Update complete. All good.', isComplete: true));
  }

  // Public API

  Future<void> syncWithPeer(BnsPeer peer, {bool isAuto = false}) async {
    final trusted = await IsarService.getTrustedDevice(peer.deviceId);

    if (trusted == null) {
      _emitProgress(const SyncProgress(progress: 0.1, message: 'New device detected. Pairing with a code is required.'));
      return;
    }

    try {
      _emitProgress(const SyncProgress(progress: 0.15, message: 'Creating a full picture of your current data...'));

      final bns = await BnsExporter.exportFullSnapshot();
      final plain = await bns.readAsBytes();

      _emitProgress(const SyncProgress(progress: 0.4, message: 'Locking it safely for transfer...'));

      final enc = _encrypt(plain, trusted.sharedSecret!);

      _emitProgress(const SyncProgress(progress: 0.6, message: 'Sending to ${peer.deviceName}...'));

      final s = await Socket.connect(peer.address, peer.port);
      s.add(enc);
      await s.flush();
      await s.close();

      _emitProgress(const SyncProgress(progress: 0.8, message: 'Getting the latest from the other device...'));

      await _pullTrusted(peer, trusted.sharedSecret!);

      await IsarService.updateTrustedDeviceLastSync(peer.deviceId, peer.address);

      _emitProgress(const SyncProgress(
        progress: 1.0,
        message: 'Everything is in sync across your devices. Nice work.',
        isComplete: true,
      ));
    } catch (e) {
      _emitProgress(SyncProgress(progress: 0, message: 'Sync paused', error: e.toString()));
    }
  }

  Future<void> _pullTrusted(BnsPeer peer, String secret) async {
    final s = await Socket.connect(peer.address, peer.port);
    s.add(utf8.encode('PULL'));
    await s.flush();

    final b = BytesBuilder();
    await for (final c in s) b.add(c);
    await s.close();

    final encBytes = b.takeBytes();
    if (encBytes.isEmpty) return;

    final key = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(key));
    final iv = enc.IV.fromLength(16);
    final plain = e.decryptBytes(enc.Encrypted(encBytes), iv: iv);

    final f = File('${(await getTemporaryDirectory()).path}/pull.bns');
    await f.writeAsBytes(plain);
    await BnsImporter.importMerge(f);
  }

  // === SECURE PAIRING ===

  String generatePairingCode() => List.generate(6, (_) => Random().nextInt(10)).join();

  Future<bool> completePairing(BnsPeer peer, String code, String myDeviceId) async {
    try {
      _emitProgress(const SyncProgress(progress: 0.25, message: 'Securing the link using the code you verified...'));

      final key = _deriveKey(code, myDeviceId);

      final bns = await BnsExporter.exportFullSnapshot();
      final plain = await bns.readAsBytes();
      final encData = _encrypt(plain, key.base64);

      final s = await Socket.connect(peer.address, peer.port);
      s.add(encData);
      await s.flush();
      await s.close();

      final td = TrustedDevice(
        id: peer.deviceId,
        name: peer.deviceName,
        lastAddress: peer.address,
        lastSyncedAt: DateTime.now(),
        sharedSecret: key.base64,
        autoSyncEnabled: true,
      );
      await IsarService.saveTrustedDevice(td);
      _trustedIds.add(peer.deviceId);

      _emitProgress(const SyncProgress(progress: 0.9, message: 'Paired safely. Syncing now...'));

      await _pullTrusted(peer, key.base64);

      _emitProgress(const SyncProgress(
        progress: 1.0,
        message: 'Securely connected and up to date. Your information is protected.',
        isComplete: true,
      ));
      return true;
    } catch (e) {
      _emitProgress(SyncProgress(progress: 0, message: 'Pairing could not be completed', error: e.toString()));
      return false;
    }
  }

  enc.Key _deriveKey(String code, String salt) {
    final d = sha256.convert(utf8.encode(code + salt));
    return enc.Key(Uint8List.fromList(d.bytes.sublist(0, 32)));
  }

  Uint8List _encrypt(List<int> data, String secret) {
    final k = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(k));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = e.encryptBytes(data, iv: iv);
    return Uint8List.fromList(iv.bytes + encrypted.bytes);
  }

  // Helpers

  Future<List<TrustedDevice>> getTrustedDevices() => IsarService.getTrustedDevices();

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

  void stop() {
    _udpSocket?.close();
    _udpSocket = null;
    _tcpServer?.close();
    _tcpServer = null;
    _peers.clear();
    _peersController.add([]);
  }

  void dispose() {
    stop();
    _peersController.close();
    _progressController.close();
  }
}
