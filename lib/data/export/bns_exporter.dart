import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';

/// Fully self-contained .bns exporter.
/// "Images" the complete current state of the app into a portable .bns file.
class BnsExporter {
  static const _uuid = Uuid();

  /// Creates a complete backup file of everything (full active data).
  /// .bns is our file to deliver full data (routines, events, active memories, etc.).
  /// Trashed items are excluded.
  /// This is the "imaging" of the user's data.
  /// Prunes first so .bns stays small (respects retention setting).
  static Future<File> exportFullSnapshot() async {
    await IsarService.pruneOldData();
    final snapshot = await IsarService.getFullSnapshot();
    final audioDir = await IsarService.getAudioDir();

    final archive = Archive();

    // Collect actual audio files referenced by captures
    final audioFiles = <File>[];
    for (final cap in snapshot.captures) {
      if (cap.audioPath != null) {
        final file = File(cap.audioPath!);
        if (await file.exists()) {
          audioFiles.add(file);
        } else {
          // Try relative inside audio dir
          final relative = File('${audioDir.path}/${cap.audioPath!.split(Platform.pathSeparator).last}');
          if (await relative.exists()) audioFiles.add(relative);
        }
      }
    }

    // manifest
    final manifest = {
      'formatVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'deviceId': _uuid.v4(), // fresh id for this export
      'deviceName': snapshot.settings.deviceName,
      'appVersion': '0.1.0+1',
      'schema': 'bns/v1',
      'audioCount': audioFiles.length,
      'totalItems': snapshot.routines.length +
          snapshot.events.length +
          snapshot.captures.length +
          snapshot.logs.length,
      'dataCompressed': true,
      'dataFormat': 'gzip+json',
    };
    archive.addFile(ArchiveFile('manifest.json', 0, utf8.encode(jsonEncode(manifest))));

    // data.json - full snapshot (GZip compressed for compact .bns - our database format)
    final data = {
      'routines': snapshot.routines.map((e) => e.toJson()).toList(),
      'events': snapshot.events.map((e) => e.toJson()).toList(),
      'captures': snapshot.captures.map((e) => e.toJson()).toList(),
      'completionLogs': snapshot.logs.map((e) => e.toJson()).toList(),
      'settings': snapshot.settings.toJson(),
    };
    final dataJson = jsonEncode(data);
    final dataBytes = utf8.encode(dataJson);
    final compressedData = GZipEncoder().encode(dataBytes) as List<int>;
    archive.addFile(ArchiveFile('data.json.gz', compressedData.length, compressedData));

    // audio/ folder inside the zip — use clean filenames
    for (final f in audioFiles) {
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        final cleanName = f.uri.pathSegments.last;
        archive.addFile(ArchiveFile('audio/$cleanName', bytes.length, bytes));
      }
    }

    final encoded = ZipEncoder().encode(archive)!;

    final docs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${docs.path}/exports');
    await exportsDir.create(recursive: true);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '').substring(0, 15);
    final fileName = 'BNS_Backup_${snapshot.settings.deviceName.replaceAll(' ', '_')}_$timestamp.bns';
    final out = File('${exportsDir.path}/$fileName');

    await out.writeAsBytes(encoded, flush: true);
    return out;
  }
}
