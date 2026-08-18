import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// WHERE BNS LIVES — asked once, answered here.
///
/// The data file, audio and exports used to be nailed to the platform
/// documents folder, and captures carried ABSOLUTE paths into the data.
/// The first machine change broke every reference (the C:\Users\Shaltiel\...
/// audio ghosts, owner QA 2026-08-09: "we have to make it not hardcoded").
///
/// A tiny bootstrap pointer — `bns_home.txt` in the platform documents
/// folder — names the chosen home. It is the ONLY thing with a fixed
/// address; everything else (bns_data.json, audio/, exports/) lives inside
/// the home it points to. No pointer (or a dead one) = the documents
/// folder, exactly as before, so nobody is forced to choose anything.
class BnsHome {
  static const String pointerFileName = 'bns_home.txt';

  static Directory? _dir;

  /// A process-pinned home (test isolation door). While set, the pointer
  /// file is never read OR written — a harness instance structurally
  /// cannot touch the live store or redirect the live app's home.
  static Directory? _forced;

  /// THE SITTING (care profiles, 2026-08-17): while the caregiver sits
  /// with one person, the active home is that profile's directory —
  /// session-only, above the pin and the pointer, never persisted here
  /// (profiles/sitting.txt remembers across launches). [rootDir] keeps
  /// answering the seat's own home so the registry never nests.
  static Directory? _sitting;

  static void sitIn(Directory? profileHome) => _sitting = profileHome;

  static bool get isSitting => _sitting != null;

  /// The caregiver's own home, ignoring any sitting — where profiles/,
  /// the registry and the seat's own store live.
  static Future<Directory> rootDir() async {
    final sat = _sitting;
    _sitting = null;
    try {
      return await dir();
    } finally {
      _sitting = sat;
    }
  }

  /// THE ISOLATION DOOR the harness always needed (2026-08-17): a
  /// `--data-dir=<path>` argument or `BNS_DATA_DIR` environment variable
  /// pins the home for THIS process only. It was documented in
  /// docs/testing-live.md and never implemented — and a Windows test
  /// seed overwrote the LIVE Level-1 store through shared Documents
  /// (caregiver report, 2026-08-16). Call from main() before the store
  /// opens; harmless when neither is given.
  static void applyStartupArgs(List<String> args) {
    String? path;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a.startsWith('--data-dir=')) {
        path = a.substring('--data-dir='.length);
      } else if (a == '--data-dir' && i + 1 < args.length) {
        // The testing guide's spelling: `--data-dir C:\temp\user1`.
        path = args[i + 1];
      }
    }
    try {
      path ??= Platform.environment['BNS_DATA_DIR'];
    } catch (_) {}
    final chosen = (path ?? '').trim();
    if (chosen.isEmpty) {
      // macOS `open` does not hand Dart the flag or the env. A dressed
      // .lN-test app must still find its sibling store (lived L2,
      // 2026-08-18 ~19:16: Person disk had 15, the running .app asked).
      _pinHarnessSiblingIfNeeded();
      return;
    }
    try {
      final d = Directory(chosen)..createSync(recursive: true);
      _forced = d;
      _dir = d;
    } catch (_) {
      // An unusable isolation path must not take the app down — it just
      // falls back to the normal home.
    }
  }

  /// Tests may pretend the process lives inside a dressed harness app.
  @visibleForTesting
  static String? debugExecutableForTest;

  static String _executablePath() =>
      debugExecutableForTest ?? Platform.resolvedExecutable;

  /// A dressed harness app sits next to its store:
  /// `.l2-test/BNS-L2.app` → `.l2-test/person/`
  /// `.l2-test/BNS-Care.app` → `.l2-test/caregiver/`
  ///
  /// `--data-dir` / `BNS_DATA_DIR` still win. This is the relaunch
  /// door: overlay + dock / `open` without args must not open the
  /// bundle's Application Support (unset 0) while the file people
  /// inspect sits at `.lN-test/person` (15). Lived isolated L2 Person
  /// 2026-08-18 ~19:16 IDT, bundle `com.whiteno1se.bns.l2person`.
  static final _harnessFolder = RegExp(r'^\.l[2-5]-test$');

  static String? harnessHomeFromExecutable(String executable) {
    final raw = executable.trim();
    if (raw.isEmpty) return null;
    var cursor = File(raw).absolute.parent;
    final walked = raw.toLowerCase();
    for (var i = 0; i < 10; i++) {
      final name = p.basename(cursor.path);
      if (_harnessFolder.hasMatch(name)) {
        final sep = p.separator;
        final isCare = walked.contains('care.app') ||
            walked.contains('bns-care') ||
            walked.contains('l2care') ||
            walked.contains('l3care') ||
            walked.contains('l4care') ||
            walked.contains('l5care') ||
            walked.contains('${sep}caregiver$sep') ||
            walked.endsWith('${sep}caregiver');
        final home = p.join(cursor.path, isCare ? 'caregiver' : 'person');
        return Directory(home).existsSync() ? home : null;
      }
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }
    return null;
  }

  static void _pinHarnessSiblingIfNeeded() {
    if (_forced != null || _sitting != null) return;
    final home = harnessHomeFromExecutable(_executablePath());
    if (home == null) return;
    try {
      final d = Directory(home);
      _forced = d;
      _dir = d;
    } catch (_) {}
  }

  /// Drop the process pin (tests only).
  static void debugClearForcedForTest() {
    _forced = null;
    _sitting = null;
    _dir = null;
    debugExecutableForTest = null;
  }

  /// The current home. Cached after the first read; [setDir] refreshes it.
  static Future<Directory> dir() async {
    final sitting = _sitting;
    if (sitting != null) return sitting;
    final forced = _forced;
    if (forced != null) return forced;
    final cached = _dir;
    if (cached != null) return cached;
    // Same pin as applyStartupArgs: a dressed harness .app finds its
    // sibling store even when main() never received --data-dir.
    _pinHarnessSiblingIfNeeded();
    if (_forced != null) return _forced!;
    final docs = await getApplicationDocumentsDirectory();
    try {
      final pointer = File('${docs.path}/$pointerFileName');
      if (await pointer.exists()) {
        final chosen = (await pointer.readAsString()).trim();
        if (chosen.isNotEmpty && await Directory(chosen).exists()) {
          final d = Directory(chosen);
          _dir = d;
          return d;
        }
        // A pointer to a missing folder (unplugged drive, renamed user)
        // falls back to documents — the app must open no matter what.
      }
    } catch (_) {}
    _dir = docs;
    return docs;
  }

  static Future<String> currentPath() async => (await dir()).path;

  /// Point the home at [newDir] and remember it for every next launch.
  /// The caller is responsible for having moved/copied the data first.
  static Future<void> setDir(Directory newDir) async {
    if (_forced != null) {
      // A pinned process may move its own home in memory, but it never
      // writes the shared pointer — the live app's home is not its to move.
      _forced = newDir;
      _dir = newDir;
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final pointer = File('${docs.path}/$pointerFileName');
    if (newDir.path == docs.path) {
      // Choosing the default again = no pointer needed at all.
      try {
        if (await pointer.exists()) await pointer.delete();
      } catch (_) {}
    } else {
      await pointer.writeAsString(newDir.path, flush: true);
    }
    _dir = newDir;
  }
}
