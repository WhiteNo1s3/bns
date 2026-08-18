import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';

/// Always-accessible quick capture entry.
/// Voice first (mic big target) + text fallback.
/// Wears the room's name — «הקלטה ותיעוד» (owner rename, 2026-08-18) —
/// with no trailing explainer; the mic on it says the how.
class QuickCaptureBar extends StatelessWidget {
  final VoidCallback onTap;

  const QuickCaptureBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.mic, size: 22),
      label: Text(L.t('Recording & notes', 'הקלטה ותיעוד')),
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }
}
