import 'package:flutter/widgets.dart';

/// One law for "is this a big screen?" — the sidebar shell and every screen
/// that hides its duplicate navigation follow the same number. WIDTH decides,
/// not the platform: an Android tablet or an iPad in landscape is a
/// desktop-sized screen and deserves the comfortable big-screen experience
/// (tablets wave, 2026-08-09). Phones and narrow windows keep the simple
/// one-column flow.
class BnsLayout {
  BnsLayout._();

  /// Logical pixels from which the sidebar shell appears.
  /// 820 keeps every phone (and tablet portrait on smaller tablets) on the
  /// familiar simple layout; landscape tablets and PCs get the sidebar.
  static const double wideMin = 820;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideMin;
}
