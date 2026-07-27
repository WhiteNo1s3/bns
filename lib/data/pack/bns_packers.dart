import 'bns_binary_packer.dart';
import 'bns3_packer.dart';
import 'bns_packer.dart';
import 'bns_zip_packer.dart';

export 'bns_binary_packer.dart';
export 'bns3_packer.dart';
export 'bns_packer.dart';
export 'bns_wire.dart';
export 'bns_zip_packer.dart';

/// Registry of all known container formats, newest preferred.
/// The importer asks the registry, never a concrete class — future formats
/// plug in here and NOWHERE else (exporter/importer/LAN stay untouched).
class BnsPackers {
  static final BnsZipPacker _zip = BnsZipPacker();
  static final BnsBinaryPacker _bns2 = BnsBinaryPacker();
  static final Bns3Packer _bns3 = Bns3Packer();

  /// All packers that can read files, newest first.
  static List<BnsPacker> get all => [_bns3, _bns2, _zip];

  /// The format every new image is written with.
  /// zip-v2 stays the default writer (rename-to-.zip transparency);
  /// bns3-v1 / bns2-v1 are full readers + race on the benchmark. Switching
  /// the writer is an owner decision on those numbers + product story.
  static BnsPacker get current => _zip;

  /// Compact original writer (BNS Wire + seal). Use when size of *data*
  /// matters more than zip transparency (e.g. future LAN delta path).
  static BnsPacker get compact => _bns3;
  /// Detect which packer claims these raw bytes, or null for foreign data.
  static BnsPacker? detect(List<int> bytes) {
    for (final p in all) {
      if (p.canHandle(bytes)) return p;
    }
    return null;
  }
}
