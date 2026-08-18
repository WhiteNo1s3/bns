/// THE VERSION LAW (owner, 2026-08-18: "we neglect the versioning, it's
/// +0.01 and an `a` at the end as this is considered ALPHA").
///
/// One human version — 0.XXa — living in lib/core/version.dart, and the
/// machine form 0.XX.0+N in pubspec. This test welds them together: bump
/// one without the other and the tree goes red. Neglect cannot return
/// quietly.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/version.dart';

void main() {
  test('kBnsVersion and pubspec speak the same alpha version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m =
        RegExp(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', multiLine: true)
            .firstMatch(pubspec);
    expect(m, isNotNull,
        reason: 'pubspec must carry the machine form 0.XX.0+N');

    final major = m!.group(1)!;
    final minor = m.group(2)!;
    expect(kBnsVersion, '$major.${minor}a',
        reason: 'the human version is the machine version wearing its a');
  });

  test('alpha wears the a until 1.0', () {
    expect(kBnsVersion.startsWith('0.'), isTrue);
    expect(kBnsVersion.endsWith('a'), isTrue,
        reason: 'the letter falls only at 1.0 — the clean, signed build');
  });
}
