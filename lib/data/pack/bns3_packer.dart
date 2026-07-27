/// BNS3 — original container + wire coding for "new heights" travel files.
///
/// Design goals (owner direction 2026-07-27):
/// - Clever compression where it still helps (structured data).
/// - Original coding (BNS Wire / BNSD), not only open ZIP+JSON.
/// - Unbreakable SHA-256 seal (same bar as zip-v2 / bns2-v1).
/// - Voice stays STORED raw (.m4a is already compressed — never re-deflate).
/// - zip-v2 remains the default *writer* for rename-to-.zip transparency;
///   BNS3 is a full reader + optional writer raced by the benchmark.
///
/// Layout (little-endian u32 lengths):
/// ```
/// "BNS3"                         magic @ 0
/// u32 manifestLen + manifest JSON  (includes packer + integrity)
/// u8  dataCodec                    1 = gzip(BNSD wire), 2 = raw BNSD
/// u32 dataLen     + data bytes     (hashed for integrity)
/// u32 audioCount
///   [ u32 nameLen + name + u32 byteLen + bytes ] × N
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'bns_packer.dart';
import 'bns_wire.dart';

class Bns3Packer implements BnsPacker {
  static const List<int> magic = [0x42, 0x4E, 0x53, 0x33]; // "BNS3"

  /// dataCodec values — packer picks the smallest at write time.
  static const int codecGzipJson = 0; // classic, often best on diary text
  static const int codecGzipWire = 1; // original BNS Wire + gzip
  static const int codecRawWire = 2; // tiny payloads, no gzip wrapper

  /// Below this encoded size, skip gzip (wrapper not worth it).
  static const int gzipThreshold = 384;

  @override
  String get formatId => 'bns3-v1';

  @override
  String get description =>
      'BNS3 original container: BNS Wire (string-pool binary) + optional gzip '
      'for data, raw audio, SHA-256 integrity. Compact where diary text lives.';

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
    // Clever path: race gzip(JSON) vs gzip(Wire) vs raw Wire — keep the
    // smallest. Diary-shaped JSON often gzip-wins; binary-heavy or
    // pool-friendly trees favor Wire. Never pay more than classic.
    final jsonUtf = utf8.encode(jsonEncode(data));
    final wire = BnsWire.encode(data);
    final candidates = <({int codec, List<int> bytes})>[];
    if (wire.length < gzipThreshold) {
      candidates.add((codec: codecRawWire, bytes: wire));
    }
    candidates.add((
      codec: codecGzipJson,
      bytes: GZipEncoder().encode(jsonUtf)!,
    ));
    if (wire.length >= gzipThreshold) {
      candidates.add((
        codec: codecGzipWire,
        bytes: GZipEncoder().encode(wire)!,
      ));
    }
    candidates.sort((a, b) => a.bytes.length.compareTo(b.bytes.length));
    final best = candidates.first;
    final codec = best.codec;
    final dataBytes = best.bytes;

    final audioHashes = <String, String>{};
    for (final audio in audioFiles) {
      audioHashes[audio.name] = sha256.convert(audio.bytes).toString();
    }

    final codecName = switch (codec) {
      codecGzipJson => 'gzip+json',
      codecGzipWire => 'gzip+bnsd',
      codecRawWire => 'bnsd',
      _ => 'unknown',
    };
    final sealedManifest = {
      ...manifest,
      'packer': formatId,
      'dataCodec': codecName,
      'integrity': {
        'algorithm': 'sha256',
        'data': sha256.convert(dataBytes).toString(),
        'audio': audioHashes,
      },
    };
    final manifestBytes = utf8.encode(jsonEncode(sealedManifest));

    final out = BytesBuilder(copy: false);
    out.add(magic);
    out.add(_u32(manifestBytes.length));
    out.add(manifestBytes);
    out.addByte(codec);
    out.add(_u32(dataBytes.length));
    out.add(dataBytes is Uint8List ? dataBytes : Uint8List.fromList(dataBytes));
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

    if (offset >= raw.length) {
      throw const FormatException(
          'This .bns file is damaged (failed the container check). '
          'Try another copy — your device data is untouched.');
    }
    final codec = raw[offset++];
    final dataBytes = take(u32());
    final audioCount = u32();
    final audioFiles = <BnsAudioEntry>[];
    for (var i = 0; i < audioCount; i++) {
      final name = utf8.decode(take(u32()));
      audioFiles.add((name: name, bytes: take(u32())));
    }

    final integrity = manifest['integrity'];
    if (integrity is Map) {
      final expectedData = integrity['data'];
      if (expectedData is String &&
          sha256.convert(dataBytes).toString() != expectedData) {
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

    final Map<String, dynamic> data;
    try {
      switch (codec) {
        case codecGzipJson:
          final plain = GZipDecoder().decodeBytes(dataBytes);
          data = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
          break;
        case codecGzipWire:
          final wire = GZipDecoder().decodeBytes(dataBytes);
          data = _mapRoot(BnsWire.decode(wire));
          break;
        case codecRawWire:
          data = _mapRoot(BnsWire.decode(dataBytes));
          break;
        default:
          throw FormatException(
              'This .bns uses an unknown data coding ($codec). '
              'Update the app, or open a zip-v2 backup.');
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'This .bns file is damaged (data would not open). '
          'Nothing was imported.');
    }

    return (manifest: manifest, data: data, audioFiles: audioFiles);
  }

  static Map<String, dynamic> _mapRoot(Object? decoded) {
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException(
        'Not a BNS backup — data root is not an object.');
  }

  static List<int> _u32(int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }
}
