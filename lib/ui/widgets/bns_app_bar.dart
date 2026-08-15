import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io' show Platform;
import 'package:go_router/go_router.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/layout.dart';

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

    // A pushed screen must always offer the way back (owner, 2026-07-26:
    // getting stuck in the memory garden with "no return to routine"). When
    // there is somewhere to return TO, the back arrow wins over any
    // decorative leading — null here lets the platform add its own back.
    //
    // On a phone's TOP-LEVEL screens the leading spot becomes תפריט — a
    // real word, opening the whole app by name (owner, 2026-08-15: "we
    // need a side menu... this ain't jail"). Never on top of a back
    // arrow, never on wide screens (the sidebar already names everything).
    final canPop = Navigator.of(context).canPop();
    final phone = !BnsLayout.isWide(context);
    // Lazy + guarded: screens pushed outside the router have no
    // GoRouterState, and the bar must never crash a screen over a menu.
    bool onMenu = false;
    if (!canPop && phone) {
      try {
        onMenu = GoRouterState.of(context).uri.path == '/menu';
      } catch (_) {}
    }
    final Widget? effectiveLeading = canPop
        ? null
        : (phone && !onMenu
            ? IconButton(
                onPressed: () => context.push('/menu'),
                tooltip: L.t('Menu', 'תפריט'),
                iconSize: 30,
                constraints:
                    const BoxConstraints(minWidth: 56, minHeight: 48),
                icon: const Icon(Icons.menu),
              )
            : leading);

    if (Platform.isIOS) {
      // Clean native iOS feel with Cupertino.
      return CupertinoNavigationBar(
        middle: Text(title),
        leading: effectiveLeading,
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
        leading: effectiveLeading,
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
        leading: effectiveLeading,
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
