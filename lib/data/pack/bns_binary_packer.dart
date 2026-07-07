import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'bns_packer.dart';

/// BNS2 — the custom length-prefixed binary container (format `bns2-v1`).
///
/// Ported from the reference-inbox prototype (2026-07-06 wave) and raised to
/// house standards the draft lacked: the SHA-256 integrity seal, hard bounds
/// checks with friendly refusals, and the pure synchronous [BnsPacker]
/// contract so it slots into the registry untouched.
///
/// Layout (all integers little-endian uint32):
/// ```
/// "BNS2"                       4-byte magic — identity at offset 0
/// manifestLen + manifest JSON  (sealed: packer + sha256 integrity block)
/// dataLen     + data.json.gz   (gzip once, exactly like zip-v2)
/// audioCount
///   [ nameLen + name(utf8) + byteLen + bytes ]  × audioCount
/// ```
///
/// Why it exists: no ZIP central directory or per-entry headers to build and
/// walk — pack/unpack is a straight memory copy, which matters for large
/// audio collections. Why zip-v2 stays the default writer: a .bns you can
/// rename to .zip and open anywhere is a transparency feature. The benchmark
/// (`test/pack_benchmark_test.dart`) is the referee; switching the writer is
/// an owner decision on those numbers.
class BnsBinaryPacker implements BnsPacker {
  static const List<int> magic = [0x42, 0x4E, 0x53, 0x32]; // "BNS2"

  @override
  String get formatId => 'bns2-v1';

  @override
  String get description =>
      'BNS2 length-prefixed binary container + SHA-256 integrity. '
      'Faster than ZIP for big collections; not zip-inspectable.';

  @override
  bool canHandle(List<int> bytes) {
    if (bytes.length < 16) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  @override
  List<int> pack({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> data,
    required List<BnsAudioEntry> audioFiles,
  }) {
    final gz = GZipEncoder().encode(utf8.encode(jsonEncode(data))) as List<int>;

    final audioHashes = <String, String>{};
    for (final audio in audioFiles) {
      audioHashes[audio.name] = sha256.convert(audio.bytes).toString();
    }
    final sealedManifest = {
      ...manifest,
      'packer': formatId,
      'integrity': {
        'algorithm': 'sha256',
        'data': sha256.convert(gz).toString(),
        'audio': audioHashes,
      },
    };
    final manifestBytes = utf8.encode(jsonEncode(sealedManifest));

    final out = BytesBuilder(copy: false);
    out.add(magic);
    out.add(_u32(manifestBytes.length));
    out.add(manifestBytes);
    out.add(_u32(gz.length));
    out.add(gz);
    out.add(_u32(audioFiles.length));
    for (final audio in audioFiles) {
      final nameBytes = utf8.encode(audio.name);
      out.add(_u32(nameBytes.length));
      out.add(nameBytes);
      out.add(_u32(audio.bytes.length));
      out.add(audio.bytes is Uint8List
          ? audio.bytes as Uint8List
          : Uint8List.fromList(audio.bytes));
    }
    return out.toBytes();
  }

  @override
  BnsUnpacked unpack(List<int> bytes) {
    if (!canHandle(bytes)) {
      throw const FormatException(
          'Not a BNS backup — only real .bns files can be imported.');
    }
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final view = ByteData.sublistView(raw);
    var offset = 4;

    Uint8List take(int length) {
      if (length < 0 || offset + length > raw.length) {
        throw const FormatException(
            'This .bns file is damaged (failed the container check). '
            'Try another copy — your device data is untouched.');
      }
      final slice = Uint8List.sublistView(raw, offset, offset + length);
      offset += length;
      return slice;
    }

    int u32() {
      if (offset + 4 > raw.length) {
        throw const FormatException(
            'This .bns file is damaged (failed the container check). '
            'Try another copy — your device data is untouched.');
      }
      final v = view.getUint32(offset, Endian.little);
      offset += 4;
      return v;
    }

    final Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(utf8.decode(take(u32()))) as Map<String, dynamic>;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Not a BNS backup — missing manifest or data inside the file.');
    }
    final gz = take(u32());
    final audioCount = u32();
    final audioFiles = <BnsAudioEntry>[];
    for (var i = 0; i < audioCount; i++) {
      final name = utf8.decode(take(u32()));
      audioFiles.add((name: name, bytes: take(u32())));
    }

    // The same unbreakable seal as zip-v2: nothing partial or altered ever
    // reaches the database.
    final integrity = manifest['integrity'];
    if (integrity is Map) {
      final expectedData = integrity['data'];
      if (expectedData is String &&
          sha256.convert(gz).toString() != expectedData) {
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

    final data = jsonDecode(utf8.decode(GZipDecoder().decodeBytes(gz)))
        as Map<String, dynamic>;

    return (manifest: manifest, data: data, audioFiles: audioFiles);
  }

  static List<int> _u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }
}
