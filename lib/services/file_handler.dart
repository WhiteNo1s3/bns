import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/platform/android_widget.dart';

/// Handles opening .bns files (file association) - cross-platform.
/// iOS (high-profile iPhone): Via Info.plist document types. Open .bns → import full data.
/// When the app is launched with a .bns path, we can import it.
class BnsFileHandler {
  static Future<void> handleLaunchWithFile(
      String path, BuildContext? context) async {
    if (!path.toLowerCase().endsWith('.bns')) return;

    final file = File(path);
    if (!await file.exists()) return;

    debugPrint('BNS file opened: $path');

    try {
      // Use merge by default for safety (user data preserved)
      await BnsImporter.importMerge(file);
      await IsarService.pruneOldData();
      AndroidBnsWidget.updateWidget();

      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Imported .bns: ${file.path.split(Platform.pathSeparator).last}. Your data is updated. You got this.')),
        );
      }
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import had a problem: $e')),
        );
      }
    }
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
