/// WHO is header-only identity — no pair, no data.
///
/// Same-Mac knock: a sibling answers WHO so Sync can show לחבר / a code.
/// The wire line is `WHO <deviceId> <boundPort> <deviceName>`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/data/sync/lan_sync_service.dart';

void main() {
  test('WHO reply round-trips a name with spaces', () {
    final line = LanSyncService.formatWhoReply(
      deviceId: 'dev-care',
      boundPort: 42428,
      deviceName: 'BNS Care L2',
    );
    expect(line, 'WHO dev-care 42428 BNS Care L2\n');
    final who = LanSyncService.parseWhoReply(line);
    expect(who, isNotNull);
    expect(who!.deviceId, 'dev-care');
    expect(who.port, 42428);
    expect(who.deviceName, 'BNS Care L2');
  });

  test('WHO parse ignores a bare request and junk', () {
    expect(LanSyncService.parseWhoReply('WHO\n'), isNull);
    expect(LanSyncService.parseWhoReply('WHO'), isNull);
    expect(LanSyncService.parseWhoReply('PAIR x y'), isNull);
    expect(LanSyncService.parseWhoReply('WHO only-two'), isNull);
    expect(LanSyncService.parseWhoReply('WHO id notaport name'), isNull);
  });

  test('WHO parse keeps extra spaces and an empty name', () {
    final who = LanSyncService.parseWhoReply('WHO  sib-l2  42428  רמה 2\n');
    expect(who, isNotNull);
    expect(who!.deviceId, 'sib-l2');
    expect(who.port, 42428);
    expect(who.deviceName, 'רמה 2');
    expect(LanSyncService.parseWhoReply('WHO sib 42428')!.deviceName, 'BNS');
  });

  test('WHO format strips newlines from the name', () {
    final line = LanSyncService.formatWhoReply(
      deviceId: 'id1',
      boundPort: 42425,
      deviceName: 'Ben\nPhon',
    );
    expect(line, 'WHO id1 42425 Ben Phon\n');
    final who = LanSyncService.parseWhoReply(line);
    expect(who!.deviceName, 'Ben Phon');
  });

  test('same-Mac loopback stays a visible peer address', () {
    expect(LanSyncService.visiblePeerAddress(null, '127.0.0.1'), '127.0.0.1');
    expect(LanSyncService.visiblePeerAddress('', '127.0.0.1'), '127.0.0.1');
    expect(
      LanSyncService.visiblePeerAddress('127.0.0.1', '192.168.31.241'),
      '192.168.31.241',
    );
    expect(
      LanSyncService.visiblePeerAddress('192.168.31.241', '127.0.0.1'),
      '192.168.31.241',
    );
  });

  test('one hung door does not drop a good sibling', () async {
    final hungSockets = <Socket>[];
    final hung = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    hung.listen(hungSockets.add); // accept, never reply, never close

    final good = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    good.listen((s) async {
      try {
        final b = BytesBuilder();
        await for (final c in s) {
          b.add(c);
          if (b.toBytes().contains(10)) break;
        }
        s.add(utf8.encode(LanSyncService.formatWhoReply(
          deviceId: 'sibling-l2',
          boundPort: good.port,
          deviceName: 'BNS L2',
        )));
        await s.flush();
      } finally {
        try {
          await s.close();
        } catch (_) {}
      }
    });

    addTearDown(() async {
      for (final s in hungSockets) {
        try {
          s.destroy();
        } catch (_) {}
      }
      await hung.close();
      await good.close();
    });

    final started = DateTime.now();
    // Same isolation as production: catch per job so wait never fails.
    WhoIdentity? hungWho;
    WhoIdentity? goodWho;
    await Future.wait([
      () async {
        try {
          hungWho = await LanSyncService.knockWhoOnce(
            '127.0.0.1',
            hung.port,
          );
        } catch (_) {}
      }(),
      () async {
        try {
          goodWho = await LanSyncService.knockWhoOnce(
            '127.0.0.1',
            good.port,
          );
        } catch (_) {}
      }(),
    ]);
    final elapsed = DateTime.now().difference(started);

    expect(goodWho, isNotNull, reason: 'a live sibling must still be seen');
    expect(goodWho!.deviceId, 'sibling-l2');
    expect(goodWho!.deviceName, 'BNS L2');
    expect(hungWho, isNull, reason: 'old door never answers WHO');
    expect(elapsed.inMilliseconds, lessThan(1500),
        reason: 'hung door must time out in ~600ms, not fold-until-close');
  });

  test('a WHO line is enough — the sibling need not close', () async {
    final open = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    open.listen((s) async {
      s.add(utf8.encode(LanSyncService.formatWhoReply(
        deviceId: 'loop-l2',
        boundPort: open.port,
        deviceName: 'רמה 2',
      )));
      await s.flush();
      // stay open — old fold waited here and לחבר stayed empty
    });
    addTearDown(open.close);

    final who = await LanSyncService.knockWhoOnce('127.0.0.1', open.port);
    expect(who, isNotNull);
    expect(who!.deviceId, 'loop-l2');
    expect(who.deviceName, 'רמה 2');
    expect(who.port, open.port);
  });
}
