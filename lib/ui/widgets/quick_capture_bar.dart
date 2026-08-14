import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';

/// Always-accessible quick capture entry.
/// Voice first (mic big target) + text fallback.
/// Will expand to full bottom sheet / dedicated screen with Record package.
class QuickCaptureBar extends StatelessWidget {
  final VoidCallback onTap;

  const QuickCaptureBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.mic, size: 22),
      label: Text(L.t('Keep this — voice or write',
          'לשמור את זה — בקול או בכתיבה')),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
