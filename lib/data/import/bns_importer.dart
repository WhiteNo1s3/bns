import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/pack/bns_file_imager.dart';
import 'package:bns/data/pack/bns_packers.dart';

/// Imports a .bns file (the reverse of imaging).
/// Supports replace-all or smart merge.
///
/// Only valid BNS images are accepted — part of the "only .bns ever traverses
/// the LAN" guarantee. Structural checks AND SHA-256 integrity verification
/// run before a single byte reaches the database.
///
/// Large files: the standard zip container is read STREAMED — every voice
/// note flows zip→disk in small chunks off the UI thread, so a .bns with
/// hours of audio imports in flat memory. The in-memory packer registry
/// remains the fallback reader for non-zip formats (LAN-sized by design).
class BnsImporter {
  /// Fast structural pre-check used by the LAN layer on decrypted payloads.
  /// Throws a friendly [FormatException] for anything no packer claims.
  static void validateBnsBytes(List<int> bytes) {
    if (BnsPackers.detect(bytes) == null) {
      throw FormatException(L.t(
          'Not a BNS backup — only real .bns files can be imported.',
          'זה לא קובץ גיבוי של BNS — אפשר לייבא רק קובצי ‎.bns‎ אמיתיים.'));
    }
  }

  /// Instant identity check without unpacking (format v2+): a genuine .bns
  /// carries `mimetype` = application/x-bns as its FIRST, uncompressed entry
  /// (EPUB-style), so the marker sits at a fixed offset in the raw bytes.
  /// ZIP local header is 30 bytes, then the 8-char name, then the content.
  static bool hasBnsMark(List<int> bytes) {
    const name = 'mimetype';
    const content = BnsZipPacker.mediaType;
    const end = 30 + name.length + content.length;
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
    // Cheap sniff from the header only — never the whole file.
    final head = <int>[];
    await for (final chunk in bnsFile.openRead(0, 64)) {
      head.addAll(chunk);
    }
    if (head.length < 4) {
      throw FormatException(L.t(
          'Not a BNS backup — only real .bns files can be imported.',
          'זה לא קובץ גיבוי של BNS — אפשר לייבא רק קובצי ‎.bns‎ אמיתיים.'));
    }

    final tempDir = await getTemporaryDirectory();
    final extractDir = Directory(
        '${tempDir.path}/bns_import_${DateTime.now().millisecondsSinceEpoch}');
    await extractDir.create(recursive: true);
    final audioExtractPath = '${extractDir.path}/audio';

    Map<String, dynamic> manifest;
    Map<String, dynamic> data;
    final extractedAudios = <File>[];

    if (head[0] == 0x50 && head[1] == 0x4B) {
      // Standard zip container (v1+v2): streamed, off the UI thread.
      final bnsPath = bnsFile.path;
      final unpacked = await Isolate.run(() => BnsFileImager.unpackToDir(
            bnsPath: bnsPath,
            audioOutDir: audioExtractPath,
          ));
      manifest = unpacked.manifest;
      data = unpacked.data;
      for (final a in unpacked.audioFiles) {
        extractedAudios.add(File(a.path));
      }
    } else {
      // Other containers (bns2 …): in-memory registry, LAN-sized by design.
      final bytes = await bnsFile.readAsBytes();
      final packer = BnsPackers.detect(bytes);
      if (packer == null) {
        throw FormatException(L.t(
            'Not a BNS backup — only real .bns files can be imported.',
            'זה לא קובץ גיבוי של BNS — אפשר לייבא רק קובצי ‎.bns‎ אמיתיים.'));
      }
      // Unpack + verify (structure, CRCs, SHA-256 integrity) in the packer.
      final unpacked = packer.unpack(bytes);
      manifest = unpacked.manifest;
      data = unpacked.data;
      for (final audio in unpacked.audioFiles) {
        final outFile = File('$audioExtractPath/${audio.name}');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(audio.bytes);
        extractedAudios.add(outFile);
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

  /// Move extracted audio files into the app's audio directory and update
  /// paths in captures. Rename (instant) with a streamed-copy fallback for
  /// temp dirs on another volume — audio bytes never pass through memory.
  static Future<List<QuickCapture>> _remapAudioPaths(
      List<QuickCapture> captures, List<File> audioFiles) async {
    final audioDir = await IsarService.getAudioDir();
    final updated = <QuickCapture>[];

    /// Land one arriving recording in the audio folder; null when the file
    /// didn't travel with this .bns (then the old path is left untouched).
    Future<String?> land(String stored) async {
      // Paths cross machines (Windows \ and phone /) — split on both, or a
      // file recorded on one platform never matches on the other.
      final originalName = stored.split(RegExp(r'[\\/]')).last;
      final matching = audioFiles.firstWhere(
        (f) => f.path.endsWith(originalName),
        orElse: () => File(''),
      );
      if (!await matching.exists()) return null;
      final destPath = '${audioDir.path}/$originalName';
      try {
        if (await File(destPath).exists()) await File(destPath).delete();
        await matching.rename(destPath);
      } on FileSystemException {
        await matching.copy(destPath);
      }
      return destPath;
    }

    for (final cap in captures) {
      if (cap.audioPath == null && cap.extraAudioPaths.isEmpty) {
        updated.add(cap);
        continue;
      }

      final mainPath =
          cap.audioPath == null ? null : await land(cap.audioPath!);
      // Extra takes land too — every voice of the moment arrives, or keeps
      // its old path so a later import can still heal it.
      final extras = <String>[];
      for (final stored in cap.extraAudioPaths) {
        extras.add(await land(stored) ?? stored);
      }

      updated.add(cap.copyWith(
        audioPath: mainPath ?? cap.audioPath,
        extraAudioPaths: extras,
      ));
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
