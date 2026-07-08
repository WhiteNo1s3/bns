import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/pack/bns_packers.dart';

/// Fully self-contained .bns exporter.
/// "Images" the complete current state of the app into a portable .bns file.
///
/// The container itself lives behind the [BnsPacker] abstraction
/// (lib/data/pack/) — this class only gathers the snapshot, decides the file
/// name, and writes atomically. Container evolution never touches this file.
///
/// Responsiveness: all heavy lifting (reading audio, compressing, packing,
/// disk write) runs in a background isolate — the UI thread never stutters.
/// Everyday saves never touch this path at all (open store, see
/// bns-format.md "Database vs travel file").
class BnsExporter {
  /// Silent lifecycle imaging: keeps ONE always-fresh .bns per device
  /// (`BNS_Latest_<device>.bns`, overwritten in place) so the user never has
  /// to press "export" to have a shareable, current database file. Called by
  /// the lifecycle guard on pause/exit; skipped upstream when nothing changed.
  static Future<File> exportLatestSnapshot() async {
    final settings = await IsarService.getSettings();
    final name = 'BNS_Latest_${settings.deviceName.replaceAll(' ', '_')}.bns';
    return exportFullSnapshot(fixedFileName: name);
  }

  /// True when this capture was chosen for the family ('family' tag,
  /// with or without a '#'). Mad-vents NEVER pass here even if tagged —
  /// a rage-moment decision to share shouldn't outlive the rage.
  static bool isFamilyTagged(Iterable<String> tags) {
    var family = false;
    for (final t in tags) {
      final tag = t.toLowerCase().replaceAll('#', '').trim();
      if (tag == 'mad-vent') return false;
      if (tag == 'family') family = true;
    }
    return family;
  }

  /// The FAMILY SHARE (owner decisions, 2026-07-06) — a filtered EXPORT,
  /// never a filtered view. Two levels, both the person's own choice:
  ///
  /// Normal: ONLY events marked "family can know" + moments tagged `family`
  /// (with their voice notes). Nothing else exists in the file, no matter
  /// how it's opened. Mad-vents never enter, even tagged.
  ///
  /// FULL CARE MODE (`Settings.fullCareMode`, the guarded last resort for
  /// the severely impaired): everything matters — the complete active data
  /// including all moments and audio, so the people easing the person's
  /// path can catch the gold in every fleeting thought.
  ///
  /// The Explorer detects `familyShare: true` and opens the family view.
  static Future<File> exportFamilyShare() async {
    final settings = await IsarService.getSettings();
    final fullCare = settings.fullCareMode;
    final snapshot = await IsarService.getFullSnapshot();

    final events = fullCare
        ? snapshot.events
        : snapshot.events.where((e) => e.shareWithFamily).toList();
    final captures = fullCare
        ? snapshot.captures.where((c) => c.deletedAt == null).toList()
        : snapshot.captures
            .where((c) => c.deletedAt == null && isFamilyTagged(c.tags))
            .toList();

    // Voice notes belonging to the shared moments travel along — hearing
    // "super annoyed at the elevator" in his own voice IS the information.
    final audioDir = await IsarService.getAudioDir();
    final audioEntries = <BnsAudioEntry>[];
    for (final cap in captures) {
      final p = cap.audioPath;
      if (p == null) continue;
      final name = p.split(Platform.pathSeparator).last.split('/').last;
      final f = File('${audioDir.path}/$name');
      if (await f.exists()) {
        audioEntries.add((name: name, bytes: await f.readAsBytes()));
      }
    }

    final manifest = {
      'formatVersion': 2,
      'mediaType': BnsZipPacker.mediaType,
      'container': 'zip (PKWARE APPNOTE) + deflate/gzip (RFC 1951/1952) + json',
      'exportedAt': DateTime.now().toIso8601String(),
      'deviceId': settings.deviceId,
      'deviceName': settings.deviceName,
      'appVersion': '0.12a',
      'schema': 'bns/v2',
      'familyShare': true,
      if (fullCare) 'fullCare': true,
      'audioCount': audioEntries.length,
      'totalItems': events.length + captures.length,
      'dataCompressed': true,
      'dataFormat': 'gzip+json',
    };
    final data = {
      'routines': fullCare
          ? snapshot.routines.map((e) => e.toJson()).toList()
          : const <Object>[],
      'events': events.map((e) => e.toJson()).toList(),
      'captures': captures.map((e) => e.toJson()).toList(),
      'completionLogs': fullCare
          ? snapshot.logs.map((e) => e.toJson()).toList()
          : const <Object>[],
      // Only the share identity — no keybinds, no preferences, no secrets.
      'settings': {'shareName': settings.effectiveShareName},
    };

    final docs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${docs.path}/exports');
    await exportsDir.create(recursive: true);
    final safeName = settings.effectiveShareName.replaceAll(' ', '_');
    final outPath = '${exportsDir.path}/BNS_Family_$safeName.bns';

    final encoded = BnsPackers.current.pack(
      manifest: manifest,
      data: data,
      audioFiles: audioEntries,
    );
    final out = File(outPath);
    final tmp = File('$outPath.tmp');
    await tmp.writeAsBytes(encoded, flush: true);
    if (await out.exists()) await out.delete();
    await tmp.rename(out.path);
    return out;
  }

  /// Creates a complete backup file of everything (full active data).
  /// Trashed items are excluded. Prunes first so .bns stays small.
  /// [fixedFileName] overwrites one stable file instead of a timestamped one.
  static Future<File> exportFullSnapshot({String? fixedFileName}) async {
    await IsarService.pruneOldData();
    final snapshot = await IsarService.getFullSnapshot();
    final audioDir = await IsarService.getAudioDir();

    // Resolve audio paths on the main isolate (cheap); heavy work goes below.
    final audioPaths = <String>[];
    for (final cap in snapshot.captures) {
      if (cap.audioPath != null) {
        final file = File(cap.audioPath!);
        if (await file.exists()) {
          audioPaths.add(file.path);
        } else {
          // Try relative inside audio dir
          final relative = File(
              '${audioDir.path}/${cap.audioPath!.split(Platform.pathSeparator).last}');
          if (await relative.exists()) audioPaths.add(relative.path);
        }
      }
    }

    final manifest = {
      'formatVersion':
          2, // v2 = identity marker + integrity seal; v1 files still import fine
      'mediaType': BnsZipPacker.mediaType,
      // Open technology this file stands on, used as-is (no ownership claimed):
      'container': 'zip (PKWARE APPNOTE) + deflate/gzip (RFC 1951/1952) + json',
      'exportedAt': DateTime.now().toIso8601String(),
      'deviceId': snapshot.settings.deviceId, // stable identity of this device
      'deviceName': snapshot.settings.deviceName,
      'appVersion': '0.12a',
      'schema': 'bns/v2',
      'audioCount': audioPaths.length,
      'totalItems': snapshot.routines.length +
          snapshot.events.length +
          snapshot.captures.length +
          snapshot.logs.length,
      'dataCompressed': true,
      'dataFormat': 'gzip+json',
    };

    final data = {
      'routines': snapshot.routines.map((e) => e.toJson()).toList(),
      'events': snapshot.events.map((e) => e.toJson()).toList(),
      'captures': snapshot.captures.map((e) => e.toJson()).toList(),
      'completionLogs': snapshot.logs.map((e) => e.toJson()).toList(),
      // The server token is a local secret: it never rides inside a .bns
      // (files get handed to doctors/helpers and cross the LAN).
      'settings': snapshot.settings.toJson()..remove('serverToken'),
    };
    // Pre-encode so only plain strings cross the isolate boundary.
    final manifestJson = jsonEncode(manifest);
    final dataJson = jsonEncode(data);

    final docs = await getApplicationDocumentsDirectory();
    final exportsDir = Directory('${docs.path}/exports');
    await exportsDir.create(recursive: true);

    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '').substring(0, 15);
    final fileName = fixedFileName ??
        'BNS_Backup_${snapshot.settings.deviceName.replaceAll(' ', '_')}_$timestamp.bns';
    final outPath = '${exportsDir.path}/$fileName';

    // All the heavy lifting — reading audio, packing, disk write — happens
    // off the UI thread. Only dart:io + pure packers inside (isolate-safe).
    await Isolate.run(() async {
      final audioEntries = <BnsAudioEntry>[];
      for (final path in audioPaths) {
        final f = File(path);
        if (await f.exists()) {
          audioEntries.add(
              (name: f.uri.pathSegments.last, bytes: await f.readAsBytes()));
        }
      }

      final encoded = BnsPackers.current.pack(
        manifest: jsonDecode(manifestJson) as Map<String, dynamic>,
        data: jsonDecode(dataJson) as Map<String, dynamic>,
        audioFiles: audioEntries,
      );

      // Atomic like the store itself: never leave a half-written .bns behind.
      final out = File(outPath);
      final tmp = File('$outPath.tmp');
      await tmp.writeAsBytes(encoded, flush: true);
      if (await out.exists()) await out.delete();
      await tmp.rename(out.path);
    });

    return File(outPath);
  }
}
