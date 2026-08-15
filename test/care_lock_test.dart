/// THE CAREGIVER'S KEY (owner decision, 2026-08-15) — the promises the
/// data layer must keep: the password itself is never stored, a fresh
/// salt every time, and a device from before the lock stays open.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/care_lock.dart';

void main() {
  test('the right password opens; a wrong one does not', () {
    final stored = makeCareLockHash('אבא1234');
    expect(verifyCareLock(stored, 'אבא1234'), isTrue);
    expect(verifyCareLock(stored, 'אבא1235'), isFalse);
    expect(verifyCareLock(stored, ''), isFalse);
    // Whitespace slips are forgiven — a phone keyboard adds them.
    expect(verifyCareLock(stored, ' אבא1234 '), isTrue);
  });

  test('the password itself appears nowhere in what is stored', () {
    final stored = makeCareLockHash('sunshine');
    expect(stored.contains('sunshine'), isFalse);
    expect(stored.split(':').length, 2, reason: 'salt:hash shape');
  });

  test('every set gets its own salt — equal passwords, different hashes',
      () {
    expect(makeCareLockHash('same') == makeCareLockHash('same'), isFalse);
  });

  test('a device from before the lock is simply open', () {
    expect(verifyCareLock('', 'anything'), isTrue);
    expect(verifyCareLock('   ', 'anything'), isTrue);
  });

  test('a corrupted stored value never opens by accident', () {
    expect(verifyCareLock('no-colon-here', 'x'), isFalse);
    expect(verifyCareLock(':', 'x'), isFalse);
  });
}
