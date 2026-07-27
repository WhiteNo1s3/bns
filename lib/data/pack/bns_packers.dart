import 'bns_binary_packer.dart';
import 'bns3_packer.dart';
import 'bns_packer.dart';
import 'bns_zip_packer.dart';

export 'bns_binary_packer.dart';
export 'bns3_packer.dart';
export 'bns_packer.dart';
export 'bns_wire.dart';
export 'bns_zip_packer.dart';

/// Registry of all known container formats.
///
/// ## Winner takes all (owner law, 2026-07-27)
/// **Every real save writes zip-v2 only** — `BnsPackers.current` / file imager
/// / exporter / LAN / silent BNS_Latest. That is the reliable portable .bns:
/// open ZIP, identity mark, gzip+json data, STORED audio, SHA-256 seal.
///
/// BNS2 and BNS3 remain **readers** (and research / patent-track coding for
/// compress-decompress IP). They never replace the save path. Importers
/// still detect them so exotic files can open; writers always use zip-v2.
class BnsPackers {
  static final BnsZipPacker _zip = BnsZipPacker();
  static final BnsBinaryPacker _bns2 = BnsBinaryPacker();
  static final Bns3Packer _bns3 = Bns3Packer();

  /// Readers, newest research formats first for detect().
  static List<BnsPacker> get all => [_bns3, _bns2, _zip];

  /// **THE save format.** Winner takes all. Never switch without a product
  /// decision that breaks rename-to-.zip + satellite + every existing file.
  static BnsPacker get current => _zip;

  /// Detect which packer can *read* these raw bytes, or null for foreign data.
  static BnsPacker? detect(List<int> bytes) {
    for (final p in all) {
      if (p.canHandle(bytes)) return p;
    }
    return null;
  }
}
