/// CARE PROFILES — one seat, many people, zero misfires.
/// The law lives in docs/care-profiles.md; this file is its hands.
///
/// A profile is a person: its OWN complete BNS home under
/// `<root>/profiles/<id>/` — their day, their audio, their trusted[],
/// their pairing. Wrong-profile push is impossible by STRUCTURE: a
/// profile's store only knows that person's devices, and the trust row
/// IS the address book.
library;

import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/data/import/bns_importer.dart';
import 'package:bns/data/local/bns_home.dart';
import 'package:bns/data/local/isar_service.dart';

class CareProfile {
  final String id;
  final String name;
  final DateTime createdAt;

  const CareProfile({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  CareProfile copyWith({String? name}) =>
      CareProfile(id: id, name: name ?? this.name, createdAt: createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CareProfile.fromJson(Map<String, dynamic> j) => CareProfile(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Where a device's trust was found when scanning every store this seat
/// holds — the answer to "who is asking?" for the sync guards.
class ProfileTrust {
  /// null = the seat's own root store.
  final String? profileId;
  final TrustedDevice device;

  const ProfileTrust({required this.profileId, required this.device});
}

class CareProfiles {
  static const _uuid = Uuid();

  static Future<Directory> _profilesRoot() async {
    final root = await BnsHome.rootDir();
    return Directory('${root.path}/profiles');
  }

  static Future<File> _indexFile() async =>
      File('${(await _profilesRoot()).path}/index.json');

  static Future<File> _sittingFile() async =>
      File('${(await _profilesRoot()).path}/sitting.txt');

  static Future<Directory> profileDir(String id) async =>
      Directory('${(await _profilesRoot()).path}/$id');

  static Future<Directory> inboxDir(String id) async =>
      Directory('${(await profileDir(id)).path}/inbox');

  static Future<List<CareProfile>> list() async {
    try {
      final f = await _indexFile();
      if (!await f.exists()) return const [];
      final raw = jsonDecode(await f.readAsString());
      return [
        for (final e in (raw as List))
          CareProfile.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _writeIndex(List<CareProfile> profiles) async {
    final f = await _indexFile();
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode([for (final p in profiles) p.toJson()]),
      flush: true,
    );
  }

  /// A new named door. The profile store's settings are seeded from the
  /// seat's own (hat ON, guided healed, same device identity) so every
  /// "am I the helper?" guard keeps answering yes in any sitting.
  static Future<CareProfile> create(String name) async {
    final seat = await IsarService.getSettings();
    final profile = CareProfile(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now(),
    );
    final dir = await profileDir(profile.id);
    await dir.create(recursive: true);
    final seeded = seat.copyWith(
      caregiverDevice: true,
      guidedMode: false,
      fullCareMode: false,
      careLevel: 1,
    );
    await File(
      '${dir.path}/bns_data.json',
    ).writeAsString(jsonEncode({'settings': seeded.toJson()}), flush: true);
    await _writeIndex([...await list(), profile]);
    return profile;
  }

  static Future<void> rename(String id, String newName) async {
    final all = await list();
    await _writeIndex([
      for (final p in all) p.id == id ? p.copyWith(name: newName.trim()) : p,
    ]);
  }

  /// Which door is open (persists across launches). Null = standing.
  static Future<String?> sittingId() async {
    try {
      final f = await _sittingFile();
      if (!await f.exists()) return null;
      final id = (await f.readAsString()).trim();
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Open [profile]'s door: swap the active store, remember the sitting,
  /// and merge anything that arrived in its inbox while it was closed
  /// (receive-first, words never lost).
  static Future<void> enter(CareProfile profile) async {
    final dir = await profileDir(profile.id);
    await dir.create(recursive: true);
    final sitting = await _sittingFile();
    await sitting.parent.create(recursive: true);
    await sitting.writeAsString(profile.id, flush: true);
    await IsarService.enterHome(dir);
    await _drainInbox(profile.id);
  }

  /// Back to the seat's own store (no person's door open).
  static Future<void> standUp() async {
    try {
      final f = await _sittingFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await IsarService.enterHome(null);
  }

  /// At launch: re-open the remembered door, if it still exists.
  static Future<CareProfile?> resumeSitting() async {
    final id = await sittingId();
    if (id == null) return null;
    final all = await list();
    for (final p in all) {
      if (p.id == id) {
        await IsarService.enterHome(await profileDir(p.id));
        await _drainInbox(p.id);
        return p;
      }
    }
    return null;
  }

  /// Pushes that arrived while this door was closed, merged now.
  static Future<void> _drainInbox(String id) async {
    try {
      final inbox = await inboxDir(id);
      if (!await inbox.exists()) return;
      final files = (await inbox.list().toList()).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        try {
          await BnsImporter.importMerge(f);
          await f.delete();
        } catch (_) {
          // A file that cannot merge stays put for the next open —
          // never silently discarded.
        }
      }
    } catch (_) {}
  }

  /// Scan the seat's OWN store and every profile store for [deviceId].
  /// The sync guards ask this: unknown-to-the-sitting-store is not
  /// unpaired — silence, never the severing word, when the device lives
  /// behind another door.
  static Future<ProfileTrust?> trustAnywhere(String deviceId) async {
    // The active store first (cheap, already loaded).
    final active = await IsarService.getTrustedDevice(deviceId);
    if (active != null) {
      final sitting = await sittingId();
      return ProfileTrust(profileId: sitting, device: active);
    }
    for (final p in await list()) {
      final t = await _trustedInStoreFile(
        File('${(await profileDir(p.id)).path}/bns_data.json'),
        deviceId,
      );
      if (t != null) return ProfileTrust(profileId: p.id, device: t);
    }
    // The seat's root store (only differs while sitting).
    if (BnsHome.isSitting) {
      final root = await BnsHome.rootDir();
      final t = await _trustedInStoreFile(
        File('${root.path}/bns_data.json'),
        deviceId,
      );
      if (t != null) return ProfileTrust(profileId: null, device: t);
    }
    return null;
  }

  static Future<TrustedDevice?> _trustedInStoreFile(
    File store,
    String deviceId,
  ) async {
    try {
      if (!await store.exists()) return null;
      final raw = jsonDecode(await store.readAsString());
      for (final e in (raw['trusted'] as List? ?? const [])) {
        final t = TrustedDevice.fromJson(e as Map<String, dynamic>);
        if (t.id == deviceId) return t;
      }
    } catch (_) {}
    return null;
  }

  /// Keep an arriving push for a closed door (already decrypted .bns).
  static Future<void> keepInInbox(String profileId, List<int> bnsBytes) async {
    final inbox = await inboxDir(profileId);
    await inbox.create(recursive: true);
    final name = 'push-${DateTime.now().millisecondsSinceEpoch}.bns';
    await File('${inbox.path}/$name').writeAsBytes(bnsBytes, flush: true);
  }

  /// SILK MIGRATION (docs/care-profiles.md): a seat from before profiles
  /// holds one person merged into its root store. At launch, that person
  /// becomes the first named door by themselves: the whole store moves
  /// into profiles/<id>/ (settings there already carry the seat's own
  /// hat), audio comes along, and the root keeps only the seat's
  /// settings. Returns the new profile, or null when nothing needed.
  static Future<CareProfile?> migrateLegacyIfNeeded() async {
    if (BnsHome.isSitting) return null;
    final settings = await IsarService.getSettings();
    if (!settings.caregiverDevice) return null;
    final trusted = await IsarService.getTrustedDevices();
    final snapshot = await IsarService.getFullSnapshot();
    // A helper's own seed thought is not a person. Trust, a day, or a
    // plan is. Captures-only used to mint an empty door named after the
    // seat — then the real person's first sync landed on root while
    // that leftover door sat in the list, and the inspector looked
    // emptied.
    // Demo first-run routines (seed-1/2/3) are the seat's, not a person.
    final ownDay = snapshot.routines.any((r) => !r.id.startsWith('seed-'));
    final holdsPerson =
        trusted.isNotEmpty || ownDay || snapshot.events.isNotEmpty;
    if (!holdsPerson) return null;

    // Already behind a named door? Don't mint a second one.
    for (final t in trusted) {
      final claim = await trustAnywhere(t.id);
      if (claim?.profileId != null) return null;
    }

    // A leftover empty door must not block adopting the real person
    // now living on root. Only refuse when we have no name to give
    // them and a door already exists.
    if (trusted.isEmpty && (await list()).isNotEmpty) return null;

    final name = trusted.isNotEmpty && trusted.first.name.trim().isNotEmpty
        ? trusted.first.name.trim()
        : (settings.shareName.trim().isNotEmpty
              ? settings.shareName.trim()
              : 'האדם שלי');

    final profile = CareProfile(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
    );
    final dir = await profileDir(profile.id);
    await dir.create(recursive: true);

    // The whole store is the moving box — data, logs, trusted, and the
    // seat's own settings (which is exactly what a profile store wears).
    final raw = await IsarService.rawStoreJson();
    await File(
      '${dir.path}/bns_data.json',
    ).writeAsString(jsonEncode(raw), flush: true);

    // The voice comes along: audio files belong to the person's moments.
    final root = await BnsHome.rootDir();
    final audio = Directory('${root.path}/audio');
    if (await audio.exists()) {
      final dest = Directory('${dir.path}/audio');
      await dest.create(recursive: true);
      await for (final f in audio.list()) {
        if (f is File) {
          final target = '${dest.path}/${f.uri.pathSegments.last}';
          try {
            await f.rename(target);
          } on FileSystemException {
            await f.copy(target);
            await f.delete();
          }
        }
      }
    }

    await _writeIndex([...await list(), profile]);
    await IsarService.clearPersonData();
    return profile;
  }
}
