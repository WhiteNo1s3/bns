import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import 'package:bns/data/pack/bns_zip_packer.dart';

/// One audio blob referenced by PATH (never loaded whole into memory).
typedef BnsAudioFileRef = ({String name, String path});

/// Result of a streamed unpack: data is parsed, audio is already ON DISK.
typedef BnsUnpackedToDisk = ({
  Map<String, dynamic> manifest,
  Map<String, dynamic> data,
  List<BnsAudioFileRef> audioFiles,
});

/// Streamed writer/reader for the standard `zip-v2` container.
///
/// The in-memory [BnsZipPacker] stays the source of truth for the FORMAT
/// (and for the LAN path + tests + satellite cross-checks); this class
/// produces and consumes byte-identical archives while keeping memory flat:
/// every audio blob streams disk→zip and zip→disk in small chunks, never
/// as one big buffer. This is what lets a .bns hold hours of recordings —
/// the whole reason the database file can "sustain large files".
///
/// Unlike the pure packers this class owns file I/O, so it lives beside the
/// registry, not inside it. It is isolate-safe (dart:io + pure deps only).
class BnsFileImager {
  BnsFileImager._();

  /// SHA-256 of a file without loading it whole (64 KB chunks).
  static Future<String> sha256OfFile(String path) async {
    final input = File(path).openRead();
    final digest = await sha256.bind(input).first;
    return digest.toString();
  }

  /// Image the given state into [outPath] as a standard **zip-v2** .bns.
  ///
  /// **Winner takes all:** every real portable save is zip-v2 — identity
  /// marker, gzip+json data, STORED audio, SHA-256 seal. No experimental
  /// container is ever written here.
  ///
  /// Reliability (owner law 2026-07-27):
  /// 1. Write to `.tmp` only.
  /// 2. **Verify** the temp file (mark + structure + integrity seal).
  /// 3. Keep the previous good file as `.prev` when replacing.
  /// 4. Rename temp → final only after verify passes.
  /// A failed verify leaves the previous good `.bns` untouched.
  static Future<void> packToFile({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> data,
    required List<BnsAudioFileRef> audioFiles,
    required String outPath,
  }) async {
    // Same default compression level as BnsZipPacker — identical output class.
    final gz = GZipEncoder().encode(utf8.encode(jsonEncode(data))) as List<int>;

    // Integrity seal — identical shape to BnsZipPacker.pack.
    final audioHashes = <String, String>{};
    for (final audio in audioFiles) {
      audioHashes[audio.name] = await sha256OfFile(audio.path);
    }
    final sealedManifest = {
      ...manifest,
      'packer': 'zip-v2',
      'integrity': {
        'algorithm': 'sha256',
        'data': sha256.convert(gz).toString(),
        'audio': audioHashes,
      },
    };

    final tmpPath = '$outPath.tmp';
    final prevPath = '$outPath.prev';
    // Stale temp from a killed run must not confuse us.
    try {
      final stale = File(tmpPath);
      if (await stale.exists()) await stale.delete();
    } catch (_) {}

    final encoder = ZipFileEncoder();
    encoder.create(tmpPath);
    try {
      // Identity marker MUST be first and STORED (fixed-offset detection).
      encoder.addArchiveFile(BnsZipPacker.mimetypeEntry());

      encoder.addArchiveFile(ArchiveFile(
          'manifest.json', 0, utf8.encode(jsonEncode(sealedManifest))));

      final dataEntry = ArchiveFile('data.json.gz', gz.length, gz);
      dataEntry.compress = false; // already gzipped — STORE
      encoder.addArchiveFile(dataEntry);

      for (final audio in audioFiles) {
        // Streams via InputFileStream; STORE — .m4a is already compressed.
        await encoder.addFile(
            File(audio.path), 'audio/${audio.name}', ZipFileEncoder.STORE);
      }
      await encoder.close();
    } catch (e) {
      try {
        encoder.closeSync();
      } catch (_) {}
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      rethrow;
    }

    // VERIFY before we touch the previous good file.
    try {
      await verifyZipV2File(tmpPath);
    } catch (e) {
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      throw FormatException(
          'Could not finish a reliable .bns save (the new file failed its '
          'own check). Your previous backup is still there. $e');
    }

    final out = File(outPath);
    // Preserve last known good as .prev (best effort).
    if (await out.exists()) {
      try {
        final prev = File(prevPath);
        if (await prev.exists()) await prev.delete();
        await out.rename(prevPath);
      } catch (_) {
        // If we can't keep .prev, still try a careful replace below.
        try {
          await out.delete();
        } catch (_) {}
      }
    }

    try {
      await File(tmpPath).rename(outPath);
    } catch (e) {
      // Restore previous good if rename failed mid-flight.
      try {
        final prev = File(prevPath);
        if (await prev.exists() && !await out.exists()) {
          await prev.rename(outPath);
        }
      } catch (_) {}
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      throw FormatException(
          'Could not put the new .bns in place. Your previous backup was '
          'kept if one existed. $e');
    }
  }

  /// Fixed-offset identity mark (same rule as [BnsImporter.hasBnsMark]).
  static bool hasZipV2Mark(List<int> bytes) {
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

  /// Post-write / pre-publish check: this file is a real zip-v2 .bns with a
  /// valid seal. Used so we never promote a corrupt temp over a good backup.
  static Future<void> verifyZipV2File(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const FormatException('Missing .bns file after save.');
    }
    final len = await file.length();
    if (len < 54) {
      throw const FormatException('Saved .bns is too small to be valid.');
    }

    final head = <int>[];
    await for (final chunk in file.openRead(0, 64)) {
      head.addAll(chunk);
      if (head.length >= 64) break;
    }
    if (!hasZipV2Mark(head)) {
      throw const FormatException(
          'Saved .bns is missing the BNS identity mark.');
    }

    final input = InputFileStream(path);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBuffer(input, verify: true);
    } catch (_) {
      input.closeSync();
      throw const FormatException(
          'Saved .bns failed the container check (CRC/structure).');
    }

    try {
      Map<String, dynamic>? manifest;
      List<int>? dataGz;
      final audioContents = <String, List<int>>{};

      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (entry.name == 'manifest.json') {
          manifest = jsonDecode(utf8.decode(entry.content as List<int>))
              as Map<String, dynamic>;
        } else if (entry.name == 'data.json.gz') {
          dataGz = entry.content as List<int>;
        } else if (entry.name.startsWith('audio/')) {
          final name = entry.name.substring('audio/'.length);
          if (name.isEmpty || name.contains('/') || name.contains('\\')) {
            continue;
          }
          final content = entry.content;
          audioContents[name] = content is List<int>
              ? content
              : Uint8List.fromList(List<int>.from(content as List));
        }
      }

      if (manifest == null || dataGz == null) {
        throw const FormatException(
            'Saved .bns is missing manifest or data.');
      }
      if (manifest['packer'] != null && manifest['packer'] != 'zip-v2') {
        throw const FormatException(
            'Saved .bns is not zip-v2 (winner format required for saves).');
      }

      // Prove data is real gzip+json (the portable contract with the Explorer).
      try {
        final plain = GZipDecoder().decodeBytes(dataGz);
        final decoded = jsonDecode(utf8.decode(plain));
        if (decoded is! Map) {
          throw const FormatException('Saved .bns data root is not an object.');
        }
      } catch (e) {
        if (e is FormatException) rethrow;
        throw const FormatException(
            'Saved .bns data would not open (gzip/json).');
      }

      final integrity = manifest['integrity'];
      if (integrity is Map) {
        final expectedData = integrity['data'];
        if (expectedData is String &&
            sha256.convert(dataGz).toString() != expectedData) {
          throw const FormatException(
              'Saved .bns failed its data integrity seal.');
        }
        final expectedAudio = integrity['audio'];
        if (expectedAudio is Map) {
          for (final e in expectedAudio.entries) {
            final name = e.key.toString();
            final expected = e.value;
            final bytes = audioContents[name];
            if (expected is! String) continue;
            if (bytes == null) {
              throw FormatException(
                  'Saved .bns is missing sealed voice note "$name".');
            }
            if (sha256.convert(bytes).toString() != expected) {
              throw FormatException(
                  'Saved .bns voice note "$name" failed its integrity seal.');
            }
          }
        }
      }
    } finally {
      input.closeSync();
    }
  }

  /// Read a .bns from disk, streaming every audio entry straight into
  /// [audioOutDir] (created if needed). Verifies the SHA-256 seal of the
  /// data payload and of every audio file; anything tampered or truncated
  /// is rejected and cleaned up — nothing partial survives.
  ///
  /// Only handles the zip container (v1+v2). Callers fall back to the
  /// in-memory packer registry for other formats (e.g. bns2), which are
  /// LAN-sized by design.
  static Future<BnsUnpackedToDisk> unpackToDir({
    required String bnsPath,
    required String audioOutDir,
  }) async {
    final input = InputFileStream(bnsPath);
    Archive archive;
    try {
      archive = ZipDecoder().decodeBuffer(input);
    } catch (_) {
      input.closeSync();
      throw const FormatException(
          'This .bns file is damaged (failed the container check). '
          'Try another copy — your device data is untouched.');
    }

    Map<String, dynamic> manifest = {};
    List<int>? dataGz;
    final extracted = <BnsAudioFileRef>[];

    Future<void> cleanupAndThrow(FormatException e) async {
      input.closeSync();
      for (final a in extracted) {
        try {
          await File(a.path).delete();
        } catch (_) {}
      }
      throw e;
    }

    try {
      await Directory(audioOutDir).create(recursive: true);
      for (final file in archive) {
        if (!file.isFile) continue;
        if (file.name == 'manifest.json') {
          manifest = jsonDecode(utf8.decode(file.content as List<int>))
              as Map<String, dynamic>;
        } else if (file.name == 'data.json.gz') {
          dataGz = file.content as List<int>;
        } else if (file.name == 'data.json') {
          // Very old exports: plain JSON — normalize like the packer does.
          dataGz = GZipEncoder().encode(file.content as List<int>) as List<int>;
        } else if (file.name.startsWith('audio/')) {
          final name = file.name.substring('audio/'.length);
          if (name.isEmpty || name.contains('/') || name.contains('\\')) {
            continue; // no path tricks inside our audio folder
          }
          final outPath = '$audioOutDir/$name';
          final out = OutputFileStream(outPath);
          try {
            file.writeContent(out); // streamed decompress → disk
          } finally {
            out.closeSync();
          }
          extracted.add((name: name, path: outPath));
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      await cleanupAndThrow(const FormatException(
          'This .bns file is damaged (failed the container check). '
          'Try another copy — your device data is untouched.'));
    }

    if (manifest.isEmpty || dataGz == null) {
      await cleanupAndThrow(const FormatException(
          'Not a BNS backup — missing manifest or data inside the file.'));
    }

    // Integrity verification (v2+); legacy v1 has no seal — structural
    // checks above still apply. Same rules as BnsZipPacker.unpack.
    final integrity = manifest['integrity'];
    if (integrity is Map) {
      final expectedData = integrity['data'];
      if (expectedData is String &&
          sha256.convert(dataGz!).toString() != expectedData) {
        await cleanupAndThrow(const FormatException(
            'This .bns file failed its integrity check (contents were altered '
            'or corrupted in transit). Nothing was imported.'));
      }
      final expectedAudio = integrity['audio'];
      if (expectedAudio is Map) {
        for (final audio in extracted) {
          final expected = expectedAudio[audio.name];
          if (expected is String &&
              await sha256OfFile(audio.path) != expected) {
            await cleanupAndThrow(FormatException(
                'Voice note "${audio.name}" failed its integrity check. '
                'Nothing was imported.'));
          }
        }
      }
    }

    final data = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(dataGz!)))
        as Map<String, dynamic>;
    input.closeSync();

    return (manifest: manifest, data: data, audioFiles: extracted);
  }
}
