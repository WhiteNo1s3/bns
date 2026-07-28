import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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

  /// ONE service for the whole app (owner, 2026-07-27: "we see too many
  /// seams"). Discovery used to live and die with the Sync SCREEN, so
  /// devices only found each other while a person sat on that screen —
  /// hopeless for someone at care level 3 or 4. The app now starts this at
  /// launch and it keeps listening quietly for the rest of the session.
  static final LanSyncService instance = LanSyncService();

  /// True once [startForApp] has run this session, so the app can start it
  /// on launch without the Sync screen fighting over it.
  bool _appStarted = false;

  /// Bring sync up for the whole app: discover, and quietly catch up with
  /// every trusted device that allows it. Safe to call repeatedly.
  Future<void> startForApp() async {
    if (_appStarted) return;
    _appStarted = true;
    try {
      final settings = await IsarService.getSettings();
      await start(deviceName: settings.effectiveShareName, autoSync: true);
    } catch (_) {
      // No Wi-Fi, a port already taken — the app itself never suffers.
      _appStarted = false;
    }
  }

  final _peers = <String, BnsPeer>{};

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _broadcastTimer;

  final StreamController<List<BnsPeer>> _peersController =
      StreamController.broadcast();
  final StreamController<SyncProgress> _progressController =
      StreamController.broadcast();

  /// Who is on the network right now — for a screen that opens after
  /// discovery has already been running, so it shows devices immediately
  /// instead of an empty list waiting for the next hello.
  List<BnsPeer> get currentPeers => _peers.values.toList();

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

    await _refreshBroadcastTargets();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!isRunning) return;
      // Networks come and go (Wi-Fi joins, VPN lifts) — keep the list live,
      // cheaply, once every few beats.
      _broadcastBeat = (_broadcastBeat + 1) % 6;
      if (_broadcastBeat == 0) await _refreshBroadcastTargets();
      _broadcastHello();
    });
    await _startTcpServer();
    _broadcastHello();

    _emitProgress(const SyncProgress(
        progress: 0.0, message: 'Looking for your other devices on Wi-Fi...'));
  }

  /// Every network this machine actually sits on gets its own hello.
  ///
  /// A limited broadcast (255.255.255.255) leaves through exactly ONE
  /// interface — whichever the routing table prefers. On a PC carrying
  /// VirtualBox/VMware/WSL adapters (owner's machine, 2026-07-27: five of
  /// them) that is often a virtual adapter, so the phone on the real Wi-Fi
  /// never hears a word. Addressing each interface's own subnet broadcast
  /// makes the OS route the packet out THAT interface.
  List<InternetAddress> _broadcastTargets = [
    InternetAddress('255.255.255.255')
  ];
  int _broadcastBeat = 0;

  Future<void> _refreshBroadcastTargets() async {
    final targets = <String>{'255.255.255.255'};
    try {
      final interfaces = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          if (addr.address.startsWith('169.254.')) continue; // link-local
          // Dart doesn't expose netmasks; /24 is the shape of virtually
          // every home LAN, and a stray broadcast costs nothing.
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } catch (_) {
      // Interface enumeration blocked — the limited broadcast still tries.
    }
    _broadcastTargets = targets.map(InternetAddress.new).toList();
  }

  List<int>? _helloBytes({required bool isReply}) {
    if (_deviceName == null) return null;
    return utf8.encode(jsonEncode({
      'magic': magic,
      'deviceName': _deviceName,
      'deviceId': _myDeviceId, // stable — trust depends on it
      'lastExport': DateTime.now().toIso8601String(),
      'port': transferPort,
      // A reply is never replied to — that alone keeps the handshake from
      // echoing forever between two devices.
      if (isReply) 'reply': true,
    }));
  }

  void _broadcastHello() {
    if (_udpSocket == null) return;
    final bytes = _helloBytes(isReply: false);
    if (bytes == null) return;
    for (final target in _broadcastTargets) {
      try {
        _udpSocket!.send(bytes, target, discoveryPort);
      } catch (_) {
        // One unreachable interface must never silence the others.
      }
    }
  }

  /// Answer a hello straight back to whoever sent it.
  ///
  /// Broadcast is often deaf in ONE direction — an Android Wi-Fi chip
  /// filtering broadcasts, a router half-isolating clients, a VPN eating
  /// the subnet. Hearing anyone is therefore enough: we answer directly,
  /// so a device that cannot hear broadcasts still learns we exist.
  void _replyHello(InternetAddress to) {
    if (_udpSocket == null) return;
    final bytes = _helloBytes(isReply: true);
    if (bytes == null) return;
    try {
      _udpSocket!.send(bytes, to, discoveryPort);
    } catch (_) {}
  }

  void _handleDiscovery(Datagram datagram) {
    try {
      final raw = utf8.decode(datagram.data);
      if (!raw.contains(magic)) return; // fast reject non-BNS traffic
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['magic'] != magic) return;

      final peerId = data['deviceId'] as String? ?? '';
      if (peerId.isEmpty || peerId == _myDeviceId) return;

      // Heard a broadcast? Answer it directly, once — the sender may be
      // unable to hear ours. Replies are never answered, so this cannot echo.
      if (data['reply'] != true) _replyHello(datagram.address);

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
      } else if (header.startsWith('REVOKE ')) {
        // No secret needed to hear "we are done" — the worst a forged
        // revoke can do is make two devices pair again, deliberately.
        await _handleRevoke(header.substring(7).trim());
      } else if (header.startsWith('PULL ')) {
        final requesterId = header.substring(5).trim();
        final trusted = await IsarService.getTrustedDevice(requesterId);
        if (trusted == null) {
          // We un-paired from this device. SAY so instead of going quiet —
          // silence looked exactly like a network hiccup, which is why the
          // other side kept showing "connected" (owner QA, 2026-07-27).
          socket.add(utf8.encode('REVOKED\n'));
          await socket.flush();
          return;
        }
        if (trusted.sharedSecret == null || !trusted.lanSyncAllowed) {
          // Paired but switched off: no data, and no revocation either.
          return;
        }
        final f = await BnsExporter.exportFullSnapshot();
        final cipher =
            await _encryptFileInIsolate(f.path, trusted.sharedSecret!);
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

    final tempPath = '${(await getTemporaryDirectory()).path}/lan_recv.bns';
    final decrypted = await _decryptToFileInIsolate(
        Uint8List.fromList(body), trusted.sharedSecret!, tempPath);
    if (decrypted == null) return;
    final temp = File(decrypted);
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

      _emitProgress(const SyncProgress(
          progress: 0.4, message: 'Locking it safely for transfer...'));

      final cipher =
          await _encryptFileInIsolate(bns.path, trusted.sharedSecret!);

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

    // "REVOKED" — the other side has un-paired from us. Drop them here too,
    // so a severed connection heals itself the moment anyone tries to sync,
    // even if the goodbye message never arrived.
    if (encBytes.length <= 16) {
      final asText = utf8.decode(encBytes, allowMalformed: true).trim();
      if (asText == 'REVOKED') {
        await _handleRevoke(peer.deviceId);
        return;
      }
    }

    final outPath = '${(await getTemporaryDirectory()).path}/pull.bns';
    final decrypted = await _decryptToFileInIsolate(
        Uint8List.fromList(encBytes), secret, outPath);
    if (decrypted == null) return;
    final f = File(decrypted);
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

  // Static + pure so they can run inside Isolate.run without capturing the
  // service (sockets/streams can't cross isolates). Crypto on a big .bns is
  // real CPU work — off the UI thread it never freezes a progress bar.

  static Uint8List _encryptBytes(List<int> data, String secret) {
    final k = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc));
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted = e.encryptBytes(data, iv: iv);
    return Uint8List.fromList(iv.bytes + encrypted.bytes);
  }

  /// Counterpart of [_encryptBytes]: first 16 bytes are the IV.
  static List<int> _decryptBytes(Uint8List data, String secret) {
    if (data.length <= 16) return const [];
    final k = enc.Key.fromBase64(secret);
    final e = enc.Encrypter(enc.AES(k, mode: enc.AESMode.cbc));
    final iv = enc.IV(Uint8List.fromList(data.sublist(0, 16)));
    return e.decryptBytes(enc.Encrypted(Uint8List.fromList(data.sublist(16))),
        iv: iv);
  }

  /// Read a .bns from disk and encrypt it, all off the UI thread.
  static Future<Uint8List> _encryptFileInIsolate(String path, String secret) {
    return Isolate.run(
        () async => _encryptBytes(await File(path).readAsBytes(), secret));
  }

  /// Decrypt to a temp .bns file, off the UI thread. Returns the file path,
  /// or null when the payload is empty/too short (wrong key, dead stream).
  static Future<String?> _decryptToFileInIsolate(
      Uint8List cipher, String secret, String outPath) {
    return Isolate.run(() async {
      final plain = _decryptBytes(cipher, secret);
      if (plain.isEmpty) return null;
      // Only a genuine .bns payload is ever accepted — wrong key, truncated
      // data, or a hostile file all fail this structural check and go nowhere.
      BnsImporter.validateBnsBytes(plain);
      await File(outPath).writeAsBytes(plain, flush: true);
      return outPath;
    });
  }

  // Helpers

  Future<List<TrustedDevice>> getTrustedDevices() =>
      IsarService.getTrustedDevices();

  /// Un-pair — and SAY SO to the other device.
  ///
  /// Owner QA (2026-07-27): "if you delete a connection we should transmit
  /// that the connection is severed." A pairing is a mutual agreement; one
  /// side dropping it must not leave the other still holding a key and a
  /// live auto-sync. Every in-memory permission goes with it, so nothing
  /// stale can keep syncing until the next restart.
  Future<void> forgetDevice(String id) async {
    final peer = await IsarService.getTrustedDevice(id);
    await IsarService.removeTrustedDevice(id);
    _trustedIds.remove(id);
    _lanAllowedIds.remove(id);
    _autoSyncedThisSession.remove(id);
    _peers.remove(id);
    _peersController.add(_peers.values.toList());

    // Tell them, best effort: an unreachable device simply learns later,
    // when its own request is refused.
    final address = _peers[id]?.address ?? peer?.lastAddress;
    if (address == null || address.isEmpty || _myDeviceId.isEmpty) return;
    try {
      final socket = await Socket.connect(address, transferPort,
          timeout: const Duration(seconds: 3));
      socket.add(utf8.encode('REVOKE $_myDeviceId\n'));
      await socket.flush();
      await socket.close();
    } catch (_) {
      // Saying goodbye is a courtesy; the revocation here already stands.
    }
  }

  /// The other side un-paired us. Drop them too — a severed connection is
  /// severed in both directions, and the person is told plainly.
  Future<void> _handleRevoke(String peerId) async {
    final known = await IsarService.getTrustedDevice(peerId);
    if (known == null) return;
    await IsarService.removeTrustedDevice(peerId);
    _trustedIds.remove(peerId);
    _lanAllowedIds.remove(peerId);
    _autoSyncedThisSession.remove(peerId);
    _peers.remove(peerId);
    _peersController.add(_peers.values.toList());
    _emitProgress(SyncProgress(
      progress: 1.0,
      message: '${known.name} ended the connection. '
          'Nothing more is shared with that device.',
      isComplete: true,
    ));
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
