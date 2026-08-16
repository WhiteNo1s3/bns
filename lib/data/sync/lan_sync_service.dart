import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/sync_policy.dart';
import 'package:bns/data/export/bns_exporter.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/sync/sync_progress.dart';
import 'package:bns/core/models/trusted_device.dart';
import 'package:bns/platform/android_widget.dart';

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

/// What came back when we asked another device to pair.
enum PairingResult {
  /// The person there typed a code and accepted.
  accepted,

  /// A clear "no" — declined, or nobody was listening there.
  declined,

  /// We couldn't reach the device at all.
  unreachable,
}

/// Both sides derived a key from the typed code — and they don't match.
/// Every transfer would decrypt to garbage; the only cure is a fresh pairing.
/// Before this existed, a mistyped code just made sync "broken" with no words
/// (owner QA, 2026-08-09: "that makes the app want the number and it syncs
/// broken").
class _CodeMismatch implements Exception {}

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
/// Wire protocol (TCP, one line header then raw bytes) — FROZEN for
/// compatibility: the owner's phone runs a 2026-07-29 build of this same
/// protocol and must keep syncing until its data is safely migrated.
///   PAIR <deviceId> <deviceName...>   → receiver prompts for code, replies "OK"/"NO"
///   PUSH <deviceId>                    → header line, then IV+ciphertext of a .bns
///   PULL <deviceId>                    → replies with IV+ciphertext of a .bns
///   REVOKE <deviceId>                  → the sender un-paired from us
class LanSyncService {
  static const int discoveryPort = 42424;
  static const String magic = 'BNS_HELLO';
  static const int transferPort = 42425;

  /// ONE service for the whole app (owner, 2026-07-27: "we see too many
  /// seams"). Discovery used to live and die with the Sync SCREEN, so
  /// devices only found each other while a person sat on that screen —
  /// hopeless for someone at care level 3 or 4. The app now starts this at
  /// launch and it keeps listening quietly for the rest of the session.
  ///
  /// NOTHING may stop it. Until 2026-08-09 the Sync screen's dispose()
  /// killed this singleton on the way out — one visit to the screen and the
  /// whole app went deaf until restart ("the pc I couldn't get to see the
  /// device anymore"). There is deliberately no dispose() anymore.
  static final LanSyncService instance = LanSyncService();

  /// Bring sync up for the whole app: discover, and quietly catch up with
  /// every trusted device that allows it. Safe to call repeatedly — also as
  /// a retry after a launch without Wi-Fi.
  Future<void> startForApp() async {
    if (isRunning) return;
    try {
      final settings = await IsarService.getSettings();
      await start(deviceName: settings.effectiveShareName, autoSync: true);
    } catch (_) {
      // No Wi-Fi, a port already taken — the app itself never suffers,
      // and the next call simply tries again.
    }
  }

  final _peers = <String, BnsPeer>{};

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _broadcastTimer;
  Timer? _changePushTimer;

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

  /// Asks the person to type the code shown on the initiating device.
  /// Return null to decline. Set app-wide at startup (main.dart), so a
  /// pairing request reaches the person on ANY screen — it used to exist
  /// only while the Sync screen was open, which read as "I pressed sync on
  /// the phone and the PC did nothing" (owner QA, 2026-08-09).
  Future<String?> Function(PairingRequest request)? onPairRequest;

  String? _deviceName;
  String _myDeviceId = '';
  bool _autoSyncEnabled = true;
  final Set<String> _trustedIds = {};
  // Per-device LAN kill switch: paired but LAN-disabled devices sync nothing.
  final Set<String> _lanAllowedIds = {};
  // Per-device auto-sync choice (the trusted card's own switch).
  final Set<String> _autoSyncIds = {};
  // Last known addresses — so known devices are POKED directly instead of
  // waiting for broadcast luck ("why are we seeking for new ones and not
  // syncing the devices").
  final Map<String, String> _trustedAddresses = {};
  // When each device last auto-synced — replaces the old once-per-session
  // latch that froze sync until restart.
  final Map<String, DateTime> _lastAutoSyncAt = {};
  // In-flight guard: one sync conversation per device at a time.
  final Set<String> _syncingWith = {};
  // True while merging data that ARRIVED from a peer — those changes must
  // not schedule a push back, or two devices would ping-pong forever.
  bool _applyingRemoteData = false;

  /// Reload trust + per-device LAN permissions from the store.
  /// Call after pairing, forgetting, or toggling switches in the UI.
  Future<void> refreshTrustPolicy() async {
    final trusted = await IsarService.getTrustedDevices();
    _trustedIds
      ..clear()
      ..addAll(trusted.map((d) => d.id));
    _lanAllowedIds
      ..clear()
      ..addAll(trusted.where((d) => d.lanSyncAllowed).map((d) => d.id));
    _autoSyncIds
      ..clear()
      ..addAll(trusted.where((d) => d.autoSyncEnabled).map((d) => d.id));
    _trustedAddresses
      ..clear()
      ..addEntries(trusted
          .where((d) => d.lastAddress.isNotEmpty)
          .map((d) => MapEntry(d.id, d.lastAddress)));
  }

  bool get isRunning => _udpSocket != null;

  /// True while a sync conversation with this device is in flight — the
  /// UI turns its Sync button into a spinner so pressing it six times
  /// does six times nothing (owner QA, 2026-08-10).
  bool isSyncingWith(String deviceId) => _syncingWith.contains(deviceId);

  Future<void> start({required String deviceName, bool autoSync = true}) async {
    if (isRunning) return;
    _deviceName = deviceName;
    _autoSyncEnabled = autoSync;

    final settings = await IsarService.getSettings();
    _myDeviceId = settings.deviceId;

    await refreshTrustPolicy();

    // TWO EARS ON ONE MACHINE (caregiver report, 2026-08-16: "after Person
    // takes both LAN ports on this Mac, Care goes deaf"). On POSIX,
    // reusePort lets a second instance keep listening for hellos instead
    // of losing the port to the first — exactly the alpha setup of Person
    // + Care side by side. Windows has no reusePort; there we fall back,
    // and a lost bind is at worst the old behavior.
    try {
      _udpSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, discoveryPort,
          reusePort: Platform.isMacOS || Platform.isLinux || Platform.isAndroid);
    } on SocketException {
      _udpSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, discoveryPort);
    }
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
      _pokeMissingTrusted();
      _evictStalePeers();
    });
    await _startTcpServer();
    _broadcastHello();
    _pokeMissingTrusted();

    _emitProgress(SyncProgress(
        progress: 0.0,
        message: L.t('Looking for your other devices on Wi-Fi...',
            'מחפשים את המכשירים האחרים שלך ב-Wi-Fi...'),
        subtle: true));
  }

  /// A burst of hellos right now — for a screen that just opened or a person
  /// who pressed "look again". Discovery beats every 5s anyway; this removes
  /// the up-to-5s "nothing is happening" gap that read as "very slow".
  void pokeDiscovery() {
    if (!isRunning) return;
    _refreshBroadcastTargets().then((_) {
      if (!isRunning) return;
      _broadcastHello();
      _pokeMissingTrusted();
      Timer(const Duration(milliseconds: 700), () {
        if (isRunning) _broadcastHello();
      });
    });
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
      // The door this instance really answers at — never the family default.
      'port': _boundPort ?? transferPort,
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

  /// Hellos aimed straight at trusted devices we can't currently see, at
  /// their last known address. Broadcast can be deaf in one direction
  /// (Android Wi-Fi chips filter it aggressively); a unicast knock usually
  /// still lands — the known device answers, and sync follows by itself.
  void _pokeMissingTrusted() {
    if (_udpSocket == null) return;
    final bytes = _helloBytes(isReply: false);
    if (bytes == null) return;
    for (final entry in _trustedAddresses.entries) {
      final seen = _peers[entry.key];
      if (seen != null && peerLooksOnline(seen.lastSeen, DateTime.now())) {
        continue;
      }
      try {
        _udpSocket!.send(bytes, InternetAddress(entry.value), discoveryPort);
      } catch (_) {}
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

      // Trusted device in sight → catch up, again and again — a cooldown,
      // not a once-per-session latch (that latch meant the SECOND change of
      // the day never traveled until someone restarted the app).
      if (shouldAutoSyncOnSight(
        autoSyncEnabled: _autoSyncEnabled && _autoSyncIds.contains(peerId),
        trusted: _trustedIds.contains(peerId),
        lanAllowed: _lanAllowedIds.contains(peerId),
        lastAutoSyncAt: _lastAutoSyncAt[peerId],
        now: DateTime.now(),
      )) {
        _lastAutoSyncAt[peerId] = DateTime.now();
        syncWithPeer(peer, isAuto: true);
      }
    } catch (_) {}
  }

  /// Ghost peers (left the network long ago) fall off the list.
  void _evictStalePeers() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere(
        (_, p) => now.difference(p.lastSeen) > kPeerEvictAfter);
    if (_peers.length != before) {
      _peersController.add(_peers.values.toList());
    }
  }

  /// Something changed locally (a routine edited, a plan answered, a capture
  /// saved). After a short debounce, every trusted device currently on the
  /// network receives the update — the silky part: nobody presses anything.
  void noteLocalDataChanged() {
    if (!isRunning || _applyingRemoteData) return;
    _changePushTimer?.cancel();
    _changePushTimer = Timer(kChangePushDebounce, () {
      final now = DateTime.now();
      for (final peer in _peers.values.toList()) {
        if (!_autoSyncEnabled) break;
        if (!_trustedIds.contains(peer.deviceId)) continue;
        if (!_lanAllowedIds.contains(peer.deviceId)) continue;
        if (!_autoSyncIds.contains(peer.deviceId)) continue;
        if (!peerLooksOnline(peer.lastSeen, now)) continue;
        _lastAutoSyncAt[peer.deviceId] = now;
        syncWithPeer(peer, isAuto: true);
      }
    });
  }

  /// The TCP port this instance actually LISTENS on. On a machine running
  /// several instances (Person + Care on one Mac) only one can own
  /// [transferPort]; the rest take the next free door and say so in their
  /// hellos. Before this, every instance CLAIMED 42425 while only one owned
  /// it — so a sync request could reach a sibling instead of its pair, and
  /// the sibling's honest "I don't know you" erased a living pairing.
  int? _boundPort;

  Future<void> _startTcpServer() async {
    for (var candidate = transferPort;
        candidate < transferPort + 8;
        candidate++) {
      try {
        _tcpServer =
            await ServerSocket.bind(InternetAddress.anyIPv4, candidate);
        _boundPort = candidate;
        _tcpServer!.listen((s) => _handleIncoming(s));
        return;
      } on SocketException {
        continue; // a sibling owns this one — try the next door
      }
    }
    // Eight busy neighbors — take any free door; hellos carry the number.
    _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _boundPort = _tcpServer!.port;
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
          if (header.startsWith('PAIR ') ||
              header.startsWith('PULL ') ||
              header.startsWith('PULL2 ')) {
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
      } else if (header.startsWith('REVOKE ')) {
        await _handleRevoke(header.substring(7).trim());
      }
    } catch (e) {
      _emitProgress(SyncProgress(
          progress: 0,
          message: L.t('Receive problem', 'תקלה בקבלה'),
          error: '$e'));
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
        await refreshTrustPolicy();
        socket.add(utf8.encode('OK\n'));
        _emitProgress(SyncProgress(
            progress: 1.0,
            message: L.t('Paired safely. The first sync starts by itself.',
                'הצימוד הושלם בבטחה. הסנכרון הראשון מתחיל מעצמו.'),
            isComplete: true));
      } else if (header.startsWith('PULL2 ')) {
        // PULL2 <requesterId> <expectedServerId> — the request names who it
        // thinks it reached. Instances on one machine share an IP, and a
        // PULL landing on the wrong sibling used to be answered REVOKED —
        // which the requester obeyed, erasing a LIVING pairing (all four
        // harness stores wiped themselves, 2026-08-16). AN ANSWER ABOUT
        // TRUST IS ONLY VALID FROM THE DEVICE IT NAMES; anyone else says
        // NOTME and the requester just waits for a fresher hello.
        final parts = header.substring(6).trim().split(RegExp(r'\s+'));
        final requesterId = parts.isEmpty ? '' : parts.first;
        final expectedId = parts.length > 1 ? parts[1] : '';
        if (expectedId != _myDeviceId) {
          socket.add(utf8.encode('NOTME\n'));
          await socket.flush();
          return;
        }
        final trusted = await IsarService.getTrustedDevice(requesterId);
        if (trusted == null) {
          // We really are who they asked for, and we really did un-pair.
          // SAY so instead of going quiet — silence looked exactly like a
          // network hiccup (owner QA, 2026-07-27).
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
      } else if (header.startsWith('PULL ')) {
        // Older devices that don't send PULL2 yet. They cannot prove who
        // they reached, so the severing word is never said here — an
        // unknown requester gets silence, which old clients already show
        // as "didn't share anything back, maybe un-paired" with re-pair
        // advice. Honest enough, and it cannot erase a living pairing.
        final requesterId = header.substring(5).trim();
        final trusted = await IsarService.getTrustedDevice(requesterId);
        if (trusted == null) return;
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

    _emitProgress(SyncProgress(
        progress: 0.75,
        message: L.t('Receiving your updated information...',
            'מקבלים את המידע המעודכן שלך...'),
        subtle: true));

    final tempPath = '${(await getTemporaryDirectory()).path}/lan_recv.bns';
    String? decrypted;
    try {
      decrypted = await _decryptToFileInIsolate(
          Uint8List.fromList(body), trusted.sharedSecret!, tempPath);
    } catch (_) {
      decrypted = null;
    }
    if (decrypted == null) {
      // Garbage from a paired device = the two sides hold different keys.
      // Say it — silence here is what made sync look haunted.
      _emitProgress(SyncProgress(
          progress: 0,
          message: L.t(
              '${trusted.name} sent something this device could not unlock.',
              '${trusted.name} שלח משהו שהמכשיר הזה לא הצליח לפתוח.'),
          error: L.t(
              'The pairing code probably didn\'t match. End the connection '
              'on both devices and pair again — a fresh code fixes this.',
              'כנראה שקוד הצימוד לא תאם. נתקו את החיבור בשני המכשירים '
              'וצמדו מחדש — קוד טרי מסדר את זה.')));
      return;
    }
    final temp = File(decrypted);
    _applyingRemoteData = true;
    try {
      await BnsImporter.importMerge(temp);
    } finally {
      _applyingRemoteData = false;
    }
    try {
      await temp.delete();
    } catch (_) {}
    // The home-screen widget shows the day too — it must not wait for the
    // app to be opened to learn what just arrived.
    AndroidBnsWidget.updateWidget();

    await IsarService.updateTrustedDeviceLastSync(
        senderId, trusted.lastAddress);
    // NOT subtle: data arriving from another device is the moment the
    // person is waiting for ("I didn't see updates on the pc") — say it.
    _emitProgress(SyncProgress(
        progress: 1.0,
        message: L.t('Update from ${trusted.name} is in. All good.',
            'העדכון מ-${trusted.name} נקלט. הכול טוב.'),
        isComplete: true));
  }

  // Public API

  /// One full conversation with a trusted device: PULL their latest first
  /// (so a mistyped pairing code is caught before we send anything), merge
  /// it in, then PUSH the combined picture back. Returns true when the
  /// whole round trip succeeded.
  Future<bool> syncWithPeer(BnsPeer peer,
      {bool isAuto = false, bool verifyingNewPairing = false}) async {
    final trusted = await IsarService.getTrustedDevice(peer.deviceId);

    if (trusted?.sharedSecret == null) {
      _emitProgress(SyncProgress(
          progress: 0.1,
          message: L.t(
              'New device detected. Pairing with a code is required.',
              'זוהה מכשיר חדש. נדרש צימוד עם קוד.')));
      return false;
    }
    if (!trusted!.lanSyncAllowed) {
      if (!isAuto) {
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t(
                'LAN transfers are switched off for ${peer.deviceName}. '
                'Flip its "LAN allowed" toggle to sync.',
                'העברות ברשת כבויות עבור ${peer.deviceName}. '
                'הפעל את "העברות ברשת" שלו כדי לסנכרן.')));
      }
      return false;
    }

    if (_syncingWith.contains(peer.deviceId)) return false;
    _syncingWith.add(peer.deviceId);
    try {
      _emitProgress(SyncProgress(
          progress: 0.2,
          message: L.t('Getting the latest from ${peer.deviceName}...',
              'מביאים את העדכני ביותר מ-${peer.deviceName}...'),
          subtle: isAuto));

      final pulled = await _pullTrusted(peer, trusted.sharedSecret!);
      if (pulled == _PullOutcome.revoked) {
        // _handleRevoke already told the person; nothing more to do here.
        return false;
      }
      if (pulled == _PullOutcome.wrongDevice) {
        // A different device answered at that address (siblings share a
        // machine, or the network reshuffled). The next hello carries the
        // right door — nothing here is worth alarming anyone about.
        if (!isAuto) {
          _emitProgress(SyncProgress(
              progress: 0,
              message: L.t(
                  'A different device answered at that address. Waiting '
                  'for a fresh hello from ${peer.deviceName}.',
                  'במקום ${peer.deviceName} ענה מכשיר אחר. מחכים לשלום '
                  'טרי ממנו.')));
        }
        return false;
      }
      if (pulled == _PullOutcome.nothing) {
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t(
                '${peer.deviceName} didn\'t share anything back.',
                '${peer.deviceName} לא שיתף שום דבר בחזרה.'),
            error: L.t(
                'On that device, this one may not be paired anymore — or '
                'LAN transfers are switched off there. If this keeps '
                'happening, end the connection on both devices and pair '
                'freshly.',
                'ייתכן שבמכשיר ההוא הצימוד למכשיר הזה כבר לא קיים — או '
                'שהעברות ברשת כבויות שם. אם זה חוזר, נתקו את החיבור בשני '
                'המכשירים וצמדו מחדש.')));
        return false;
      }

      _emitProgress(SyncProgress(
          progress: 0.55,
          message: L.t('Creating a full picture of your current data...',
              'יוצרים תמונה מלאה של המידע הנוכחי שלך...'),
          subtle: isAuto));

      final bns = await BnsExporter.exportFullSnapshot();

      _emitProgress(SyncProgress(
          progress: 0.7,
          message: L.t('Locking it safely for transfer...',
              'נועלים את המידע בבטחה להעברה...'),
          subtle: isAuto));

      final cipher =
          await _encryptFileInIsolate(bns.path, trusted.sharedSecret!);

      _emitProgress(SyncProgress(
          progress: 0.85,
          message: L.t('Sending to ${peer.deviceName}...',
              'שולחים אל ${peer.deviceName}...'),
          subtle: isAuto));

      final s = await Socket.connect(peer.address, peer.port,
          timeout: const Duration(seconds: 15));
      s.add(utf8.encode('PUSH $_myDeviceId\n'));
      s.add(cipher);
      await s.flush();
      await s.close();

      await IsarService.updateTrustedDeviceLastSync(
          peer.deviceId, peer.address);
      _lastAutoSyncAt[peer.deviceId] = DateTime.now();

      _emitProgress(SyncProgress(
        progress: 1.0,
        message: L.t(
            'Everything is in sync with ${peer.deviceName}. Nice work.',
            'הכול מסונכרן עם ${peer.deviceName}. עבודה יפה.'),
        isComplete: true,
        subtle: isAuto,
      ));
      return true;
    } on _CodeMismatch {
      if (verifyingNewPairing) {
        // The very first sync after pairing is the honesty check: keys
        // don't match, so the pairing is broken from birth. Undo it here
        // (and tell the other side) so both screens offer a clean retry.
        await forgetDevice(peer.deviceId);
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t(
                'The code didn\'t match on both sides.',
                'הקוד לא תאם בשני הצדדים.'),
            error: L.t(
                'It happens. Pair again with a fresh code — type it '
                'carefully on ${peer.deviceName}, and it will hold.',
                'זה קורה. צמדו שוב עם קוד טרי — הקלד אותו בזהירות '
                'במכשיר ${peer.deviceName}, וזה יחזיק.')));
      } else {
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t(
                'This device and ${peer.deviceName} no longer hold the '
                'same key.',
                'המכשיר הזה ו-${peer.deviceName} כבר לא מחזיקים את אותו '
                'מפתח.'),
            error: L.t(
                'End the connection on both devices and pair again — a '
                'fresh code fixes this.',
                'נתקו את החיבור בשני המכשירים וצמדו מחדש — קוד טרי מסדר '
                'את זה.')));
      }
      return false;
    } catch (e) {
      if (isAuto) {
        // A trusted device that just left the network is everyday life,
        // not an alarm. The next beat will try again.
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t(
                '${peer.deviceName} slipped away mid-sync. It will catch '
                'up when it\'s back.',
                '${peer.deviceName} התנתק באמצע הסנכרון. הוא ישלים את '
                'הפער כשיחזור.'),
            subtle: true));
      } else {
        _emitProgress(SyncProgress(
            progress: 0,
            message: L.t('Couldn\'t reach ${peer.deviceName} right now.',
                'לא הצלחנו להגיע אל ${peer.deviceName} כרגע.'),
            error: L.t(
                'Check that both devices are on the same Wi-Fi and the '
                'app is open there, then try again. ($e)',
                'ודאו ששני המכשירים באותו Wi-Fi ושהאפליקציה פתוחה שם, '
                'ונסו שוב. ($e)')));
      }
      return false;
    } finally {
      _syncingWith.remove(peer.deviceId);
    }
  }

  Future<_PullOutcome> _pullTrusted(BnsPeer peer, String secret) async {
    final s = await Socket.connect(peer.address, peer.port,
        timeout: const Duration(seconds: 15));
    // Name who we think we reached — only THAT device may answer about
    // trust. A sibling instance at the same address says NOTME instead.
    s.add(utf8.encode('PULL2 $_myDeviceId ${peer.deviceId}\n'));
    await s.flush();

    final encBytes = Uint8List.fromList(await s
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
        .timeout(const Duration(minutes: 10)));
    await s.close();

    if (encBytes.isEmpty) return _PullOutcome.nothing;

    // "REVOKED" — the other side has un-paired from us. Drop them here too,
    // so a severed connection heals itself the moment anyone tries to sync,
    // even if the goodbye message never arrived.
    if (encBytes.length <= 16) {
      final asText = utf8.decode(encBytes, allowMalformed: true).trim();
      if (asText == 'REVOKED') {
        // With PULL2 this can only come from the device we named — a real
        // revocation, never a stranger answering the family door.
        await _handleRevoke(peer.deviceId);
        return _PullOutcome.revoked;
      }
      if (asText == 'NOTME') return _PullOutcome.wrongDevice;
    }

    final outPath = '${(await getTemporaryDirectory()).path}/pull.bns';
    String? decrypted;
    try {
      decrypted = await _decryptToFileInIsolate(encBytes, secret, outPath);
    } catch (_) {
      decrypted = null;
    }
    // Real bytes arrived but the key can't open them: the two devices
    // derived different keys from the pairing codes they were given.
    if (decrypted == null) throw _CodeMismatch();

    final f = File(decrypted);
    _applyingRemoteData = true;
    try {
      await BnsImporter.importMerge(f);
    } finally {
      _applyingRemoteData = false;
    }
    try {
      await f.delete();
    } catch (_) {}
    AndroidBnsWidget.updateWidget();
    return _PullOutcome.gotData;
  }

  // === SECURE PAIRING ===
  // Initiator: shows a code + sends "PAIR" with its id/name. The other user
  // TYPES the code there. Both derive the same key; nothing secret on the wire.

  String generatePairingCode() =>
      List.generate(6, (_) => Random.secure().nextInt(10)).join();

  /// Ask [peer] to pair, RIGHT NOW — the request goes out the moment the
  /// code appears on this screen, so the other device prompts for the code
  /// while the person is looking at it. (The old flow only sent the request
  /// after a "I typed it there" button — the other device sat silent until
  /// a button that claimed the typing already happened. Owner, 2026-08-09:
  /// "the button is deceptive.")
  ///
  /// Waits generously (typing takes time), then either saves the trust or
  /// reports plainly what happened.
  Future<PairingResult> requestPairing(BnsPeer peer, String code) async {
    try {
      final s = await Socket.connect(peer.address, peer.port,
          timeout: const Duration(seconds: 10));
      s.add(utf8.encode('PAIR $_myDeviceId ${_deviceName ?? 'BNS Device'}\n'));
      await s.flush();

      final reply = utf8
          .decode(await s
              .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk))
              .timeout(const Duration(minutes: 3)))
          .trim();
      await s.close();

      if (reply != 'OK') return PairingResult.declined;

      final key = deriveKey(code, _myDeviceId);
      await IsarService.saveTrustedDevice(TrustedDevice(
        id: peer.deviceId,
        name: peer.deviceName,
        lastAddress: peer.address,
        lastSyncedAt: DateTime.now(),
        sharedSecret: key.base64,
        autoSyncEnabled: true,
      ));
      await refreshTrustPolicy();
      return PairingResult.accepted;
    } on TimeoutException {
      return PairingResult.declined;
    } catch (_) {
      return PairingResult.unreachable;
    }
  }

  /// The first sync right after pairing doubles as the code check: it pulls
  /// first, so a mismatched key surfaces immediately as "the code didn't
  /// match" instead of a lifetime of silent broken syncs.
  Future<bool> verifyNewPairing(BnsPeer peer) =>
      syncWithPeer(peer, verifyingNewPairing: true);

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
    final lastKnownAddress = _peers[id]?.address ?? peer?.lastAddress;
    await IsarService.removeTrustedDevice(id);
    _trustedIds.remove(id);
    _lanAllowedIds.remove(id);
    _autoSyncIds.remove(id);
    _trustedAddresses.remove(id);
    _lastAutoSyncAt.remove(id);
    _peers.remove(id);
    _peersController.add(_peers.values.toList());

    // Tell them, best effort: an unreachable device simply learns later,
    // when its own request is refused.
    if (lastKnownAddress == null ||
        lastKnownAddress.isEmpty ||
        _myDeviceId.isEmpty) {
      return;
    }
    // A re-installed device gets a NEW identity, leaving its old entry
    // behind as a ghost at the SAME address. Forgetting the ghost must not
    // send a goodbye there — the device would obediently sever the LIVING
    // pairing too (it only knows us by our one id). Ghost cleanup is
    // local; a real goodbye goes only where no newer pairing lives.
    final others = await IsarService.getTrustedDevices();
    if (others.any((d) => d.id != id && d.lastAddress == lastKnownAddress)) {
      return;
    }
    try {
      // Prefer the door the peer last announced; the family default may
      // belong to a sibling instance on that machine.
      final port = _peers[id]?.port ?? transferPort;
      final socket = await Socket.connect(lastKnownAddress, port,
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
    _autoSyncIds.remove(peerId);
    _trustedAddresses.remove(peerId);
    _lastAutoSyncAt.remove(peerId);
    _peers.remove(peerId);
    _peersController.add(_peers.values.toList());
    _emitProgress(SyncProgress(
      progress: 1.0,
      message: L.t(
          '${known.name} ended the connection. Nothing more is shared '
          'with that device.',
          '${known.name} סיים את החיבור. שום דבר לא משותף יותר עם '
          'המכשיר הזה.'),
      isComplete: true,
    ));
  }

  void setAutoSync(bool v) => _autoSyncEnabled = v;

  Future<File> manualExport() => BnsExporter.exportFullSnapshot();

  Future<void> manualImport(File f, {bool replace = false}) async {
    await (replace ? BnsImporter.importReplace(f) : BnsImporter.importMerge(f));
  }

  void _emitProgress(SyncProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  /// Pause the machinery (name change restarts, tests). The app itself
  /// never calls this to "clean up" — sync is a lifelong resident.
  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _changePushTimer?.cancel();
    _changePushTimer = null;
    _udpSocket?.close();
    _udpSocket = null;
    await _tcpServer?.close();
    _tcpServer = null;
    _peers.clear();
    if (!_peersController.isClosed) _peersController.add([]);
  }
}

/// What a PULL round actually produced.
enum _PullOutcome { gotData, nothing, revoked, wrongDevice }
