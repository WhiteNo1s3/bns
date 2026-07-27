/// BNS Wire (BNSD) — original binary coding for BNS structured data.
///
/// Purpose: the travel form of `data.json` without JSON key bloat.
/// Common keys and repeated strings live once in a string pool; values are
/// typed tags. Already-compressed voice notes are NOT handled here — they
/// stay raw in the container (re-compressing .m4a is waste).
///
/// Layout:
/// ```
/// "BNSD"              4-byte magic
/// u16le version       (= 1)
/// u32le poolCount
///   [ u32le len + utf8 ] × poolCount
/// value…              root is always a map (the data object)
/// ```
///
/// Value tags (one byte):
///   0x00 null | 0x01 false | 0x02 true
///   0x10 int64 le | 0x11 float64 le
///   0x20 string-ref (u32le pool index)
///   0x30 array (u32le count + values)
///   0x40 map   (u32le count + (string-ref, value) pairs)
///
/// Pure, isolate-safe, no plugins. Roundtrip is lossless for JSON-shaped
/// trees produced by `jsonDecode` (Map/List/num/String/bool/null).
library;

import 'dart:convert';
import 'dart:typed_data';

class BnsWire {
  BnsWire._();

  static const List<int> magic = [0x42, 0x4E, 0x53, 0x44]; // "BNSD"
  static const int version = 1;

  static const int tNull = 0x00;
  static const int tFalse = 0x01;
  static const int tTrue = 0x02;
  static const int tInt = 0x10;
  static const int tFloat = 0x11;
  static const int tStr = 0x20;
  static const int tArr = 0x30;
  static const int tMap = 0x40;

  /// Encode a JSON-shaped value (root should be a Map for BNS data).
  static Uint8List encode(Object? root) {
    final pool = <String>[];
    final indexOf = <String, int>{};

    int intern(String s) {
      final existing = indexOf[s];
      if (existing != null) return existing;
      final i = pool.length;
      pool.add(s);
      indexOf[s] = i;
      return i;
    }

    // First walk: collect every string (map keys + string values).
    void collect(Object? v) {
      if (v is String) {
        intern(v);
      } else if (v is List) {
        for (final e in v) {
          collect(e);
        }
      } else if (v is Map) {
        v.forEach((k, val) {
          intern(k.toString());
          collect(val);
        });
      }
    }

    collect(root);

    final body = BytesBuilder(copy: false);

    void u32(int n) {
      final b = ByteData(4)..setUint32(0, n, Endian.little);
      body.add(b.buffer.asUint8List());
    }

    void u16(int n) {
      final b = ByteData(2)..setUint16(0, n, Endian.little);
      body.add(b.buffer.asUint8List());
    }

    void writeValue(Object? v) {
      if (v == null) {
        body.addByte(tNull);
        return;
      }
      if (v is bool) {
        body.addByte(v ? tTrue : tFalse);
        return;
      }
      if (v is int) {
        body.addByte(tInt);
        final b = ByteData(8)..setInt64(0, v, Endian.little);
        body.add(b.buffer.asUint8List());
        return;
      }
      if (v is double) {
        // JSON numbers that fit in int often arrive as int; doubles stay float.
        if (v.isFinite && v == v.truncateToDouble() &&
            v >= -9223372036854775808.0 &&
            v <= 9223372036854775807.0) {
          writeValue(v.toInt());
          return;
        }
        body.addByte(tFloat);
        final b = ByteData(8)..setFloat64(0, v, Endian.little);
        body.add(b.buffer.asUint8List());
        return;
      }
      if (v is num) {
        // Other num (e.g. from custom codecs) — prefer int when exact.
        if (v is int || v == v.roundToDouble()) {
          writeValue(v.toInt());
        } else {
          writeValue(v.toDouble());
        }
        return;
      }
      if (v is String) {
        body.addByte(tStr);
        u32(intern(v));
        return;
      }
      if (v is List) {
        body.addByte(tArr);
        u32(v.length);
        for (final e in v) {
          writeValue(e);
        }
        return;
      }
      if (v is Map) {
        body.addByte(tMap);
        u32(v.length);
        v.forEach((k, val) {
          u32(intern(k.toString()));
          writeValue(val);
        });
        return;
      }
      // Last resort: stringify unknown objects so packing never dies.
      body.addByte(tStr);
      u32(intern(v.toString()));
    }

    // Header + pool + root value.
    final out = BytesBuilder(copy: false);
    out.add(magic);
    final ver = ByteData(2)..setUint16(0, version, Endian.little);
    out.add(ver.buffer.asUint8List());
    final poolCount = ByteData(4)..setUint32(0, pool.length, Endian.little);
    out.add(poolCount.buffer.asUint8List());
    for (final s in pool) {
      final utf = utf8.encode(s);
      final len = ByteData(4)..setUint32(0, utf.length, Endian.little);
      out.add(len.buffer.asUint8List());
      out.add(utf);
    }
    writeValue(root);
    out.add(body.toBytes());
    return out.toBytes();
  }

  /// Decode a BNSD buffer back to a JSON-shaped tree.
  static Object? decode(List<int> bytes) {
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (raw.length < 10) {
      throw const FormatException('BNS wire data is too short.');
    }
    for (var i = 0; i < 4; i++) {
      if (raw[i] != magic[i]) {
        throw const FormatException('Not BNS wire data (bad magic).');
      }
    }
    final view = ByteData.sublistView(raw);
    var o = 4;
    final ver = view.getUint16(o, Endian.little);
    o += 2;
    if (ver != version) {
      throw FormatException(
          'Unsupported BNS wire version $ver (this app reads v$version).');
    }
    final poolCount = view.getUint32(o, Endian.little);
    o += 4;
    final pool = <String>[];
    for (var i = 0; i < poolCount; i++) {
      if (o + 4 > raw.length) {
        throw const FormatException('BNS wire pool is truncated.');
      }
      final len = view.getUint32(o, Endian.little);
      o += 4;
      if (len < 0 || o + len > raw.length) {
        throw const FormatException('BNS wire string is truncated.');
      }
      pool.add(utf8.decode(Uint8List.sublistView(raw, o, o + len)));
      o += len;
    }

    Object? readValue() {
      if (o >= raw.length) {
        throw const FormatException('BNS wire value is truncated.');
      }
      final tag = raw[o++];
      switch (tag) {
        case tNull:
          return null;
        case tFalse:
          return false;
        case tTrue:
          return true;
        case tInt:
          if (o + 8 > raw.length) {
            throw const FormatException('BNS wire int is truncated.');
          }
          final v = view.getInt64(o, Endian.little);
          o += 8;
          return v;
        case tFloat:
          if (o + 8 > raw.length) {
            throw const FormatException('BNS wire float is truncated.');
          }
          final v = view.getFloat64(o, Endian.little);
          o += 8;
          return v;
        case tStr:
          if (o + 4 > raw.length) {
            throw const FormatException('BNS wire string-ref is truncated.');
          }
          final idx = view.getUint32(o, Endian.little);
          o += 4;
          if (idx >= pool.length) {
            throw const FormatException('BNS wire string-ref is out of range.');
          }
          return pool[idx];
        case tArr:
          if (o + 4 > raw.length) {
            throw const FormatException('BNS wire array is truncated.');
          }
          final n = view.getUint32(o, Endian.little);
          o += 4;
          final list = <Object?>[];
          for (var i = 0; i < n; i++) {
            list.add(readValue());
          }
          return list;
        case tMap:
          if (o + 4 > raw.length) {
            throw const FormatException('BNS wire map is truncated.');
          }
          final n = view.getUint32(o, Endian.little);
          o += 4;
          final map = <String, dynamic>{};
          for (var i = 0; i < n; i++) {
            if (o + 4 > raw.length) {
              throw const FormatException('BNS wire map key is truncated.');
            }
            final idx = view.getUint32(o, Endian.little);
            o += 4;
            if (idx >= pool.length) {
              throw const FormatException(
                  'BNS wire map key ref is out of range.');
            }
            map[pool[idx]] = readValue();
          }
          return map;
        default:
          throw FormatException('Unknown BNS wire tag 0x${tag.toRadixString(16)}.');
      }
    }

    return readValue();
  }

  /// Encode then measure: raw JSON utf8 vs BNSD wire (for docs/bench).
  static ({int jsonBytes, int wireBytes}) measure(Object? root) {
    final jsonBytes = utf8.encode(jsonEncode(root)).length;
    final wireBytes = encode(root).length;
    return (jsonBytes: jsonBytes, wireBytes: wireBytes);
  }
}
