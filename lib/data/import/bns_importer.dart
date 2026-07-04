import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';

/// Imports a .bns file (the reverse of imaging).
/// Supports replace-all or smart merge.
class BnsImporter {
  /// Reads a .bns file and returns parsed data + manifest.
  static Future<({
    Map<String, dynamic> manifest,
    List<Routine> routines,
    List<CalendarEvent> events,
    List<QuickCapture> captures,
    List<CompletionLog> logs,
    AppSettings settings,
    List<File> audioFiles, // temporarily extracted
  })> readBns(File bnsFile) async {
    final bytes = await bnsFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    Map<String, dynamic> manifest = {};
    Map<String, dynamic> data = {};
    final extractedAudios = <File>[];

    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory('${tempDir.path}/bns_import_${DateTime.now().millisecondsSinceEpoch}');
    await extractDir.create(recursive: true);

    for (final file in archive) {
      if (file.isFile) {
        final content = file.content as List<int>;

        if (file.name == 'manifest.json') {
          manifest = jsonDecode(utf8.decode(content));
        } else if (file.name == 'data.json') {
          data = jsonDecode(utf8.decode(content));
        } else if (file.name.startsWith('audio/')) {
          final outFile = File('${extractDir.path}/${file.name}');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(content);
          extractedAudios.add(outFile);
        }
      }
    }

    // Convert JSON to models
    final routines = (data['routines'] as List? ?? [])
        .map((j) => Routine.fromJson(j as Map<String, dynamic>))
        .toList();
    final events = (data['events'] as List? ?? [])
        .map((j) => CalendarEvent.fromJson(j as Map<String, dynamic>))
        .toList();
    final captures = (data['captures'] as List? ?? [])
        .map((j) => QuickCapture.fromJson(j as Map<String, dynamic>))
        .toList();
    final logs = (data['completionLogs'] as List? ?? [])
        .map((j) => CompletionLog.fromJson(j as Map<String, dynamic>))
        .toList();

    AppSettings settings;
    if (data['settings'] != null) {
      settings = AppSettings.fromJson(data['settings'] as Map<String, dynamic>);
    } else {
      settings = AppSettings(
        deviceName: manifest['deviceName'] ?? 'Imported Device',
        retentionDays: 14,
      );
    }

    return (
      manifest: manifest,
      routines: routines,
      events: events,
      captures: captures,
      logs: logs,
      settings: settings,
      audioFiles: extractedAudios,
    );
  }

  /// Copy extracted audio files into the app's audio directory and update paths in captures.
  static Future<List<QuickCapture>> _remapAudioPaths(
    List<QuickCapture> captures, List<File> audioFiles) async {
    final audioDir = await IsarService.getAudioDir();
    final updated = <QuickCapture>[];

    for (final cap in captures) {
      if (cap.audioPath == null) {
        updated.add(cap);
        continue;
      }

      final originalName = cap.audioPath!.split(Platform.pathSeparator).last;
      final matching = audioFiles.firstWhere(
        (f) => f.path.endsWith(originalName),
        orElse: () => File(''),
      );

      if (await matching.exists()) {
        final dest = File('${audioDir.path}/$originalName');
        await dest.writeAsBytes(await matching.readAsBytes());
        updated.add(cap.copyWith(audioPath: dest.path));
      } else {
        updated.add(cap);
      }
    }
    return updated;
  }

  /// Full replace of local data with the backup (nuclear but simple).
  static Future<void> importReplace(File bnsFile) async {
    final parsed = await readBns(bnsFile);
    final remappedCaptures = await _remapAudioPaths(parsed.captures, parsed.audioFiles);

    await IsarService.replaceAllData(
      routines: parsed.routines,
      events: parsed.events,
      captures: remappedCaptures,
      logs: parsed.logs,
      settings: parsed.settings,
    );
    // Prune to respect local retention (keeps files small)
    await IsarService.pruneOldData();
  }

  /// Smart merge (last write wins where timestamps exist).
  static Future<void> importMerge(File bnsFile) async {
    final parsed = await readBns(bnsFile);
    final remappedCaptures = await _remapAudioPaths(parsed.captures, parsed.audioFiles);

    await IsarService.mergeData(
      routines: parsed.routines,
      events: parsed.events,
      captures: remappedCaptures,
      logs: parsed.logs,
      incomingSettings: parsed.settings,
    );
    await IsarService.pruneOldData();
  }
}
