/// GETTING A .bns OUT OF THE APP — the honest half of "your data is yours".
///
/// Owner QA, 2026-08-15: "I couldn't save on android, it lied, it created a
/// file on my downloads or at any folder for that matter."
///
/// It wasn't lying so much as speaking about a place the person cannot go.
/// Every export is written inside the BNS home, and on Android that home is
/// app-private internal storage (`/data/user/0/<pkg>/app_flutter/exports`):
/// invisible to every file manager, unreachable over USB, and DELETED with
/// the app. A backup you cannot find — and that dies exactly when you need
/// it (an uninstall) — is not a backup.
///
/// So the file is still written internally (LAN sync and the auto-image both
/// rely on that copy), and then handed to the system's own save sheet so it
/// lands somewhere real: Downloads, Drive, wherever the person points it.
/// Desktops already write to a folder a human can open, so there the path is
/// simply reported truthfully.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Where a .bns ended up, and whether the person can actually reach it.
class SavedOut {
  /// The path to show. Null when nothing was saved outward.
  final String? path;

  /// True when the copy landed somewhere the person chose / can open.
  final bool reachable;

  /// True when the person dismissed the system save sheet — not a failure,
  /// just a "no thanks". The internal copy still exists.
  final bool cancelled;

  const SavedOut({this.path, required this.reachable, this.cancelled = false});
}

class BnsSaveOut {
  /// True where the app's own folders are off-limits to the person and the
  /// system save sheet is the only honest way out.
  static bool get needsSystemSheet => Platform.isAndroid || Platform.isIOS;

  /// Hand [file] to the person. On phones this opens the system save sheet;
  /// on desktop the file already sits in a folder they can open.
  ///
  /// Never throws — a backup flow must not end in a red error.
  static Future<SavedOut> saveCopy(
    File file, {
    String? dialogTitle,
  }) async {
    try {
      if (!needsSystemSheet) {
        return SavedOut(path: file.path, reachable: true);
      }
      // The sheet needs the bytes themselves. A .bns is packed with audio
      // streamed in chunks precisely to keep memory flat, so this read is
      // the one moment it is held whole — acceptable for a deliberate,
      // occasional backup, and the only route Android offers.
      final bytes = await file.readAsBytes();
      final chosen = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileNameOf(file.path),
        bytes: bytes,
      );
      if (chosen == null || chosen.trim().isEmpty) {
        return const SavedOut(path: null, reachable: false, cancelled: true);
      }
      return SavedOut(path: chosen, reachable: true);
    } catch (_) {
      // The internal copy is already written; say so rather than pretend.
      return SavedOut(path: file.path, reachable: false);
    }
  }

  /// Last path segment, whichever separator the platform used.
  static String fileNameOf(String path) =>
      path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

  /// The folder part, for telling a desktop person where to look.
  static String folderOf(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? path : path.substring(0, i);
  }
}
