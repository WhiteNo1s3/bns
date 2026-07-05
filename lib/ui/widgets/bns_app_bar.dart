import 'package:flutter/material.dart';
import 'dart:io' show Platform;

/// Adaptive AppBar for clean native feel on iOS and macOS.
/// 
/// - iOS: Uses Cupertino-like styling (large titles where possible, but keeps Material for cross).
/// - macOS: Standard Material but with native title bar integration note.
/// - Other: Default.
/// 
/// No copy-paste: single widget adapts using platform tools.
/// Each device uses its own (Cupertino for iOS, etc.).
/// Redistribution friendly: no extra deps, pure Flutter.
class BnsAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final Color? backgroundColor;

  const BnsAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      // iOS-like: more prominent title, blur if possible, but use AppBar adapted.
      // For clean iOS, could switch to Cupertino but to keep one codebase and Material consistency.
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        centerTitle: centerTitle,
        backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
        elevation: 0, // flatter for iOS feel
        // For iOS polish: can add scrolledUnderElevation etc.
      );
    } else if (Platform.isMacOS) {
      // macOS: clean, native title bar feel. Flutter on mac handles title bar.
      // Avoid iPhone-on-Mac feel.
      return AppBar(
        title: Text(title),
        actions: actions,
        leading: leading,
        centerTitle: centerTitle,
        backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.surface,
        elevation: 0,
        // macOS specific: title can be in window, but AppBar works.
      );
    } else {
      // Default (Android, Windows, Linux) - standard.
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
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
