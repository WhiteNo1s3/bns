/// Container abstraction for BNS portable images (idea: 2026-07-05 reference
/// wave, "container evolution plan"). The exporter, importer, and LAN layer
/// speak ONLY to this interface — the concrete container (zip today, anything
/// faster tomorrow) can evolve without touching any of them again.
///
/// Philosophy:
/// - Live DB = the open store (instant atomic saves). Never the .bns.
/// - .bns = fresh, portable image for spreading (LAN + any file method).
/// - Recreated whole on every imaging (a half-old file cannot exist).
/// - Unbreakable: every v2+ image carries SHA-256 integrity for its payload;
///   unpack verifies before a single byte reaches the database.
/// - Versioned: `formatId` travels in the manifest; the registry
///   (bns_packers.dart) detects the right packer from raw bytes, so old
///   files keep working forever.
library;

/// One audio blob inside an image.
typedef BnsAudioEntry = ({String name, List<int> bytes});

/// Result of unpacking an image.
typedef BnsUnpacked = ({
  Map<String, dynamic> manifest,
  Map<String, dynamic> data,
  List<BnsAudioEntry> audioFiles,
});

/// Contract every BNS container implementation fulfills.
///
/// Implementations must be PURE (no dart:io, no plugins, no globals): they
/// transform bytes only. That makes every packer isolate-safe (heavy work
/// never blocks the UI) and directly unit-testable. Callers own file I/O and
/// atomic temp+rename writes.
abstract class BnsPacker {
  /// Unique identifier, e.g. "zip-v2". Written into the manifest.
  String get formatId;

  /// Human description (shown in About/CLI contexts).
  String get description;

  /// Fast sniff: could these bytes be this packer's format?
  /// Must be cheap (header check), never throw.
  bool canHandle(List<int> bytes);

  /// Build the single self-contained image.
  /// Implementations add integrity information to the manifest they write.
  List<int> pack({
    required Map<String, dynamic> manifest,
    required Map<String, dynamic> data,
    required List<BnsAudioEntry> audioFiles,
  });

  /// Read an image back into components, VERIFYING integrity where the
  /// format provides it. Throws [FormatException] with a human-friendly
  /// message on anything invalid, tampered, or truncated.
  BnsUnpacked unpack(List<int> bytes);
}
