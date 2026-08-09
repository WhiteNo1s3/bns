import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/sync_policy.dart';

void main() {
  final now = DateTime(2026, 8, 9, 12, 0);

  group('shouldAutoSyncOnSight', () {
    test('a trusted, allowed device never synced before syncs immediately',
        () {
      expect(
        shouldAutoSyncOnSight(
          autoSyncEnabled: true,
          trusted: true,
          lanAllowed: true,
          lastAutoSyncAt: null,
          now: now,
        ),
        isTrue,
      );
    });

    test('syncs AGAIN after the cooldown — not once per session (the old bug)',
        () {
      final justSynced = shouldAutoSyncOnSight(
        autoSyncEnabled: true,
        trusted: true,
        lanAllowed: true,
        lastAutoSyncAt: now.subtract(const Duration(minutes: 2)),
        now: now,
      );
      final coolAgain = shouldAutoSyncOnSight(
        autoSyncEnabled: true,
        trusted: true,
        lanAllowed: true,
        lastAutoSyncAt: now.subtract(kAutoSyncCooldown),
        now: now,
      );
      expect(justSynced, isFalse, reason: 'inside cooldown — wait');
      expect(coolAgain, isTrue,
          reason: 'cooldown passed — the device catches up again by itself');
    });

    test('untrusted, LAN-off, or auto-sync-off devices never auto-sync', () {
      expect(
        shouldAutoSyncOnSight(
          autoSyncEnabled: true,
          trusted: false,
          lanAllowed: true,
          lastAutoSyncAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldAutoSyncOnSight(
          autoSyncEnabled: true,
          trusted: true,
          lanAllowed: false,
          lastAutoSyncAt: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldAutoSyncOnSight(
          autoSyncEnabled: false,
          trusted: true,
          lanAllowed: true,
          lastAutoSyncAt: null,
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('peerLooksOnline', () {
    test('a fresh hello is online; long silence is not', () {
      expect(
          peerLooksOnline(now.subtract(const Duration(seconds: 4)), now),
          isTrue);
      expect(
          peerLooksOnline(now.subtract(const Duration(seconds: 12)), now),
          isTrue,
          reason: 'a couple of lost hello packets must not read as offline');
      expect(
          peerLooksOnline(now.subtract(const Duration(minutes: 1)), now),
          isFalse);
    });
  });
}
