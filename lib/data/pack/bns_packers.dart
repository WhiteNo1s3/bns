import 'bns_binary_packer.dart';
import 'bns_packer.dart';
import 'bns_zip_packer.dart';

export 'bns_binary_packer.dart';
export 'bns_packer.dart';
export 'bns_zip_packer.dart';

/// Registry of all known container formats, newest preferred.
/// The importer asks the registry, never a concrete class — future formats
/// plug in here and NOWHERE else (exporter/importer/LAN stay untouched).
class BnsPackers {
  static final BnsZipPacker _zip = BnsZipPacker();
  static final BnsBinaryPacker _bns2 = BnsBinaryPacker();

  /// All packers that can read files, newest first.
  static List<BnsPacker> get all => [_bns2, _zip];

  /// The format every new image is written with.
  /// zip-v2 stays the writer (rename-to-.zip transparency is a feature);
  /// bns2-v1 is a full READER — switching the writer is an owner decision
  /// backed by the benchmark numbers.
  static BnsPacker get current => _zip;

  /// Detect which packer claims these raw bytes, or null for foreign data.
  static BnsPacker? detect(List<int> bytes) {
    for (final p in all) {
      if (p.canHandle(bytes)) return p;
    }
    return null;
  }
}
