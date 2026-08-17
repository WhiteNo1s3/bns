import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:bns/core/models/calendar_event.dart';
import 'package:bns/core/need_help.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/data/pack/bns_file_imager.dart';
import 'package:bns/data/pack/bns_packers.dart';

/// Fully self-contained .bns exporter.
/// "Images" the complete current state of the app into a portable .bns file.
///
/// **Always zip-v2** (winner takes all). Reliable method:
/// gather snapshot → stream pack to temp → verify seal → keep `.prev` →
/// promote. See [BnsFileImager.packToFile].
///
/// Responsiveness: heavy work runs in a background isolate. Everyday live
/// edits never touch this path (open store, see bns-format.md).
class BnsExporter {
  /// Silent lifecycle imaging: keeps ONE always-fresh **zip-v2** .bns per
  /// device (`BNS_Latest_<device>.bns`) so a shareable file always exists
  /// without pressing export. Previous good file kept as `.prev`.
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
  /// never a filtered view. The person's own choice of width:
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
    return exportCareWindow(
      settings.fullCareMode
          ? FamilyShareLevel.fullCare
          : FamilyShareLevel.chosenFamily,
      filePrefix: 'BNS_Family',
    );
  }

  /// THE CARE WINDOW (the per-level wall, 2026-08-17) — what LAN sync
  /// hands a peer wearing the helper hat. Same law as the family file,
  /// now with the level-1 width the sync path never had:
  ///
  ///  - [FamilyShareLevel.asksOnly] (level 1): ONLY opened Need-help asks.
  ///    No plans, no routines, no logs — a skip or a mood is never an ask.
  ///  - [FamilyShareLevel.chosenFamily] (level 2): chosen plans +
  ///    family-tagged moments (asks ride along — they carry the family
  ///    tag). Mad-vents never, even tagged.
  ///  - [FamilyShareLevel.fullCare] (levels 3–4): everything active,
  ///    rants included — the frustration IS the signal.
  ///
  /// Every width ships a settings STUB (shareName only): the helper gets
  /// the person's DAY, never their identity, keys, or preferences —
  /// hats cannot travel inside a care window at all.
  static Future<File> exportCareWindow(
    FamilyShareLevel width, {
    String filePrefix = 'BNS_CareWindow',
  }) async {
    final settings = await IsarService.getSettings();
    final fullCare = width == FamilyShareLevel.fullCare;
    final asksOnly = width == FamilyShareLevel.asksOnly;
    final snapshot = await IsarService.getFullSnapshot();

    final events = fullCare
        ? snapshot.events
        : asksOnly
            ? const <CalendarEvent>[]
            : snapshot.events.where((e) => e.shareWithFamily).toList();
    final captures = fullCare
        ? snapshot.captures.where((c) => c.deletedAt == null).toList()
        : asksOnly
            ? snapshot.captures
                .where((c) => c.deletedAt == null && level1ShareAllows(c))
                .toList()
            : snapshot.captures
                .where((c) => c.deletedAt == null && isFamilyTagged(c.tags))
                .toList();

    // Voice notes belonging to the shared moments travel along — hearing
    // "super annoyed at the elevator" in his own voice IS the information.
    // Referenced by path: they stream into the file, never through memory
    // (full care mode ships EVERY recording — that can be a lot of audio).
    final audioEntries = <BnsAudioFileRef>[];
    for (final cap in captures) {
      // EVERY take travels, not just the first — a moment can hold more
      // than one recording and none of them may be left behind.
      for (final stored in cap.allAudioPaths) {
        final resolved = await IsarService.resolveAudioPath(stored);
        if (resolved == null) continue;
        final f = File(resolved);
        audioEntries.add((name: f.uri.pathSegments.last, path: f.path));
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
      'careWindow': width.name,
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

    final home = await BnsHome.dir();
    final exportsDir = Directory('${home.path}/exports');
    await exportsDir.create(recursive: true);
    final safeName = settings.effectiveShareName.replaceAll(' ', '_');
    final outPath = '${exportsDir.path}/${filePrefix}_$safeName.bns';

    // Streamed + atomic (temp+rename inside packToFile), same zip-v2 format.
    final manifestJson = jsonEncode(manifest);
    final dataJson = jsonEncode(data);
    await Isolate.run(() async {
      await BnsFileImager.packToFile(
        manifest: jsonDecode(manifestJson) as Map<String, dynamic>,
        data: jsonDecode(dataJson) as Map<String, dynamic>,
        audioFiles: audioEntries,
        outPath: outPath,
      );
    });
    return File(outPath);
  }

  /// Creates a complete backup file of everything (full active data).
  /// Trashed items are excluded. Prunes first so .bns stays small.
  /// [fixedFileName] overwrites one stable file instead of a timestamped one.
  static Future<File> exportFullSnapshot({String? fixedFileName}) async {
    await IsarService.pruneOldData();
    final snapshot = await IsarService.getFullSnapshot();

    // Resolve audio paths on the main isolate (cheap); heavy work goes
    // below. resolveAudioPath also heals paths recorded on OTHER machines
    // by falling back to the same filename in the current audio folder.
    final audioPaths = <String>[];
    for (final cap in snapshot.captures) {
      // Every take of every moment — a second recording is not a lesser one.
      for (final stored in cap.allAudioPaths) {
        final resolved = await IsarService.resolveAudioPath(stored);
        if (resolved != null) audioPaths.add(resolved);
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

    final home = await BnsHome.dir();
    final exportsDir = Directory('${home.path}/exports');
    await exportsDir.create(recursive: true);

    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '').substring(0, 15);
    final fileName = fixedFileName ??
        'BNS_Backup_${snapshot.settings.deviceName.replaceAll(' ', '_')}_$timestamp.bns';
    final outPath = '${exportsDir.path}/$fileName';

    // All the heavy lifting — hashing audio, packing, disk write — happens
    // off the UI thread. Audio STREAMS disk→zip in small chunks (never one
    // big buffer), so a .bns full of recordings exports in flat memory —
    // this is what lets the database file sustain large audio collections.
    // Atomic temp+rename happens inside packToFile.
    await Isolate.run(() async {
      final audioRefs = <BnsAudioFileRef>[];
      for (final path in audioPaths) {
        final f = File(path);
        if (await f.exists()) {
          audioRefs.add((name: f.uri.pathSegments.last, path: f.path));
        }
      }

      await BnsFileImager.packToFile(
        manifest: jsonDecode(manifestJson) as Map<String, dynamic>,
        data: jsonDecode(dataJson) as Map<String, dynamic>,
        audioFiles: audioRefs,
        outPath: outPath,
      );
    });

    return File(outPath);
  }
}
