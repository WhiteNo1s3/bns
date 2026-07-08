import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/pack/bns_packers.dart';

/// Imports a .bns file (the reverse of imaging).
/// Supports replace-all or smart merge.
///
/// Only valid BNS images are accepted — part of the "only .bns ever traverses
/// the LAN" guarantee. The container work happens behind the [BnsPacker]
/// registry: the right format is detected from raw bytes, structural checks
/// AND SHA-256 integrity verification run inside the packer, and anything
/// invalid, tampered, or truncated is rejected before a single byte reaches
/// the database.
class BnsImporter {
  /// Fast structural pre-check used by the LAN layer on decrypted payloads.
  /// Throws a friendly [FormatException] for anything no packer claims.
  static void validateBnsBytes(List<int> bytes) {
    if (BnsPackers.detect(bytes) == null) {
      throw const FormatException(
          'Not a BNS backup — only real .bns files can be imported.');
    }
  }

  /// Instant identity check without unpacking (format v2+): a genuine .bns
  /// carries `mimetype` = application/x-bns as its FIRST, uncompressed entry
  /// (EPUB-style), so the marker sits at a fixed offset in the raw bytes.
  /// ZIP local header is 30 bytes, then the 8-char name, then the content.
  static bool hasBnsMark(List<int> bytes) {
    const name = 'mimetype';
    const content = BnsZipPacker.mediaType;
    final end = 30 + name.length + content.length;
    if (bytes.length < end) return false;
    if (bytes[0] != 0x50 || bytes[1] != 0x4B) return false;
    final nameBytes = bytes.sublist(30, 30 + name.length);
    final contentBytes = bytes.sublist(30 + name.length, end);
    return String.fromCharCodes(nameBytes) == name &&
        String.fromCharCodes(contentBytes) == content;
  }

  /// Reads a .bns file and returns parsed data + manifest.
  static Future<
      ({
        Map<String, dynamic> manifest,
        List<Routine> routines,
        List<CalendarEvent> events,
        List<QuickCapture> captures,
        List<CompletionLog> logs,
        AppSettings settings,
        List<File> audioFiles, // temporarily extracted
      })> readBns(File bnsFile) async {
    final bytes = await bnsFile.readAsBytes();

    final packer = BnsPackers.detect(bytes);
    if (packer == null) {
      throw const FormatException(
          'Not a BNS backup — only real .bns files can be imported.');
    }
    // Unpack + verify (structure, CRCs, SHA-256 integrity) inside the packer.
    final unpacked = packer.unpack(bytes);
    final manifest = unpacked.manifest;
    final data = unpacked.data;

    // Extract audio blobs to temp files for the remap step.
    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(
        '${tempDir.path}/bns_import_${DateTime.now().millisecondsSinceEpoch}');
    await extractDir.create(recursive: true);

    final extractedAudios = <File>[];
    for (final audio in unpacked.audioFiles) {
      final outFile = File('${extractDir.path}/audio/${audio.name}');
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(audio.bytes);
      extractedAudios.add(outFile);
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
        deviceName: manifest['deviceName'] as String? ?? 'Imported Device',
        retentionDays: 20,
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
    final remappedCaptures =
        await _remapAudioPaths(parsed.captures, parsed.audioFiles);

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
    final remappedCaptures =
        await _remapAudioPaths(parsed.captures, parsed.audioFiles);

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
