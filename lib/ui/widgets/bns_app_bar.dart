import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io' show Platform;

/// Adaptive AppBar for clean native feel on iOS and macOS.
///
/// - iOS: Uses CupertinoNavigationBar for native iOS look (large titles, etc.).
/// - macOS: Standard AppBar but clean, uses platform tools.
/// - Avoid copy-paste: one widget, platform detection.
/// - Redistribution friendly: no extra deps.
/// - Bars iOS/mac like, not copy of Android.
class BnsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final Color? backgroundColor;
  final bool hideOnDesktopWide; // PC shell provides modern sidebar menu

  const BnsAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.backgroundColor,
    this.hideOnDesktopWide = false,
  });

  bool get _shouldHideForDesktop {
    if (!hideOnDesktopWide) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldHideForDesktop) {
      // Modern PC sidebar shell owns the navigation chrome + selection menu.
      // Keep a tiny spacer so content doesn't jump.
      return const SizedBox(height: 2);
    }

    if (Platform.isIOS) {
      // Clean native iOS feel with Cupertino.
      return CupertinoNavigationBar(
        middle: Text(title),
        leading: leading,
        trailing: actions != null && actions!.isNotEmpty
            ? Row(mainAxisSize: MainAxisSize.min, children: actions!)
            : null,
        backgroundColor: backgroundColor ?? CupertinoColors.systemBackground,
      );
    } else if (Platform.isMacOS) {
      // Clean native macOS: standard but minimal, platform native title.
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        centerTitle: centerTitle,
        backgroundColor:
            backgroundColor ?? Theme.of(context).colorScheme.surface,
        elevation: 0,
        toolbarHeight: 44, // mac like
      );
    } else {
      // Default for Android/Windows/Linux - Material, but can be styled per platform if needed.
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        centerTitle: centerTitle,
        backgroundColor: backgroundColor,
      );
    }
  }

  @override
  Size get preferredSize {
    if (_shouldHideForDesktop) return const Size.fromHeight(2);
    if (Platform.isIOS) return const Size.fromHeight(44);
    return const Size.fromHeight(kToolbarHeight);
  }
}
