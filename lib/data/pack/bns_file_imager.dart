import 'dart:convert';
import 'dart:io';

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

  /// Image the given state into [outPath] as a standard zip-v2 .bns.
  /// Audio travels disk→zip streamed; only data.json.gz (small) is in memory.
  /// Writes are atomic: temp file first, rename on success.
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
    } catch (_) {
      try {
        encoder.closeSync();
      } catch (_) {}
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      rethrow;
    }

    final out = File(outPath);
    if (await out.exists()) await out.delete();
    await File(tmpPath).rename(outPath);
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
