/// WHO is header-only identity — no pair, no data.
///
/// Same-Mac knock: a sibling answers WHO so Sync can show לחבר / a code.
/// The wire line is `WHO <deviceId> <boundPort> <deviceName>`.
library;

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
}
