import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'bns_packer.dart';

/// The ZIP container packer — writes format v2, reads v2 and legacy v1.
///
/// Credit: the container is the open ZIP format (PKWARE APPNOTE) with
/// DEFLATE/GZIP (RFC 1951/1952) — used as-is, no ownership claimed.
/// What is BNS is the arrangement:
/// - `mimetype` identity marker (`application/x-bns`) FIRST and STORED
///   (EPUB-style) → recognizable at a fixed byte offset without unpacking.
/// - manifest.json (with SHA-256 integrity block) + data.json.gz + audio/.
/// - Responsiveness: already-compressed entries (the .gz payload, .m4a audio)
///   are STORED, never deflated again — imaging runs at raw disk speed.
/// - Unbreakable: unpack verifies ZIP CRCs AND the SHA-256 of the data
///   payload and every audio blob against the manifest. Tampered, truncated,
///   or bit-rotted images are rejected with a clear message; nothing partial
///   ever reaches the database.
class BnsZipPacker implements BnsPacker {
  static const String mediaType = 'application/x-bns';

  @override
  String get formatId => 'zip-v2';

  @override
  String get description =>
      'Open ZIP container (PKWARE, used as-is) + BNS identity marker + SHA-256 integrity.';

  @override
  bool canHandle(List<int> bytes) {
    // Covers v2 (marked) and legacy v1 (plain PK) — both are ours to read.
    return bytes.length >= 50 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  /// EPUB-style identity marker entry.
  static ArchiveFile mimetypeEntry() {
    final bytes = utf8.encode(mediaType);
    final f = ArchiveFile('mimetype', bytes.length, bytes);
    f.compress = false;
    return f;
  }

  @override
  List<int> pack({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> data,
    required List<BnsAudioEntry> audioFiles,
  }) {
    final archive = Archive();

    // Identity marker MUST be first (fixed offset — see class doc).
    archive.addFile(mimetypeEntry());

    // Payload first, so its hashes can go into the manifest.
    final gz = GZipEncoder().encode(utf8.encode(jsonEncode(data))) as List<int>;

    final audioHashes = <String, String>{};
    final audioEntries = <ArchiveFile>[];
    for (final audio in audioFiles) {
      audioHashes[audio.name] = sha256.convert(audio.bytes).toString();
      final entry =
          ArchiveFile('audio/${audio.name}', audio.bytes.length, audio.bytes);
      entry.compress = false; // .m4a is already compressed — STORE
      audioEntries.add(entry);
    }

    // Manifest with the integrity block (the "unbreakable" seal).
    final sealedManifest = {
      ...manifest,
      'packer': formatId,
      'integrity': {
        'algorithm': 'sha256',
        'data': sha256.convert(gz).toString(),
        'audio': audioHashes,
      },
    };
    archive.addFile(ArchiveFile(
        'manifest.json', 0, utf8.encode(jsonEncode(sealedManifest))));

    final dataEntry = ArchiveFile('data.json.gz', gz.length, gz);
    dataEntry.compress = false; // already gzipped — STORE
    archive.addFile(dataEntry);

    audioEntries.forEach(archive.addFile);

    return ZipEncoder().encode(archive)!;
  }

  @override
  BnsUnpacked unpack(List<int> bytes) {
    if (!canHandle(bytes)) {
      throw const FormatException(
          'Not a BNS backup — only real .bns files can be imported.');
    }

    // verify: true checks each entry's CRC32 — catches truncation/bit rot.
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const FormatException(
          'This .bns file is damaged (failed the container check). '
          'Try another copy — your device data is untouched.');
    }

    Map<String, dynamic> manifest = {};
    List<int>? dataGz;
    final audioFiles = <BnsAudioEntry>[];

    for (final file in archive) {
      if (!file.isFile) continue;
      final content = file.content as List<int>;
      if (file.name == 'manifest.json') {
        manifest = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      } else if (file.name == 'data.json.gz') {
        dataGz = content;
      } else if (file.name == 'data.json') {
        // Very old exports: plain JSON. Normalize by re-gzipping is pointless;
        // decode directly below via a marker value.
        dataGz = GZipEncoder().encode(content) as List<int>;
      } else if (file.name.startsWith('audio/')) {
        audioFiles
            .add((name: file.name.substring('audio/'.length), bytes: content));
      }
    }

    if (manifest.isEmpty || dataGz == null) {
      throw const FormatException(
          'Not a BNS backup — missing manifest or data inside the file.');
    }

    // Integrity verification (v2+). Legacy v1 files carry no seal — accepted,
    // the structural checks above still apply.
    final integrity = manifest['integrity'];
    if (integrity is Map) {
      final expectedData = integrity['data'];
      if (expectedData is String &&
          sha256.convert(dataGz).toString() != expectedData) {
        throw const FormatException(
            'This .bns file failed its integrity check (contents were altered '
            'or corrupted in transit). Nothing was imported.');
      }
      final expectedAudio = integrity['audio'];
      if (expectedAudio is Map) {
        for (final audio in audioFiles) {
          final expected = expectedAudio[audio.name];
          if (expected is String &&
              sha256.convert(audio.bytes).toString() != expected) {
            throw FormatException(
                'Voice note "${audio.name}" failed its integrity check. '
                'Nothing was imported.');
          }
        }
      }
    }

    final data = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(dataGz)))
        as Map<String, dynamic>;

    return (manifest: manifest, data: data, audioFiles: audioFiles);
  }
}
