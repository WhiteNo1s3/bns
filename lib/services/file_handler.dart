import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/export/bns_exporter.dart'; // for future import logic

/// Handles opening .bns files (file association) - cross-platform.
/// iOS (high-profile iPhone): Via Info.plist document types. Open .bns → import full data.
/// When the app is launched with a .bns path, we can import it.
class BnsFileHandler {
  static Future<void> handleLaunchWithFile(String path, BuildContext? context) async {
    if (!path.toLowerCase().endsWith('.bns')) return;

    final file = File(path);
    if (!await file.exists()) return;

    // For MVP: show a simple dialog or auto import
    // In a real app use the BnsImporter (to be implemented)
    debugPrint('BNS file opened: $path');

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opened .bns file: ${file.path.split(Platform.pathSeparator).last}. Import UI coming soon.')),
      );
    }

    // TODO: Implement full import using archive + IsarService
    // await BnsImporter.importFromFile(file);
  }

  /// Call this early in main if args passed on desktop
  static void checkDesktopArgs(List<String> args, BuildContext? context) {
    for (final arg in args) {
      if (arg.toLowerCase().endsWith('.bns')) {
        handleLaunchWithFile(arg, context);
        break;
      }
    }
  }
}
