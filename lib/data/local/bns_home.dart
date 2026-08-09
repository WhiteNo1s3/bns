import 'dart:io';

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

  /// The current home. Cached after the first read; [setDir] refreshes it.
  static Future<Directory> dir() async {
    final cached = _dir;
    if (cached != null) return cached;
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
