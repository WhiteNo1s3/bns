import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/features/wake/wake_controls.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// THE WAKE ROOM (owner, 2026-08-19: "it can be its own button on bottom
/// or in the hamburger menu whatever you see fits"). Its door lives in
/// the menu — the map of the house — and the wake also keeps its seat in
/// the Tomorrow room, where the day is built. Same controls in both;
/// this room adds the words that explain the two layers.
class WakeScreen extends StatelessWidget {
  const WakeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: BnsAppBar(title: L.t('The wake', 'השכמה')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              L.t(
                  'BNS rings the morning with a reason: the ring carries the '
                  'first things of your day. You can also put a copy in the '
                  'phone\'s own clock — the songs live there, and its alarms '
                  'ring no matter what.',
                  'BNS מצלצל את הבוקר עם סיבה: הצלצול נושא את הדברים הראשונים '
                  'של היום שלך. אפשר לשתול עותק גם בשעון של הטלפון — שם גרים '
                  'השירים, והשעון שלו מצלצל ויהי מה.'),
              style: text.bodyMedium
                  ?.copyWith(height: 1.4, color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          const WakeControls(showSeatLine: true, showTitle: false),
        ],
      ),
      // The no-dead-end guarantee: a pinned worded way back, every width.
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.tonal(
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.pop();
            } else {
              context.go('/');
            }
          },
          style:
              FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child:
              Text(L.t('Back', 'חזרה'), style: const TextStyle(fontSize: 17)),
        ),
      ),
    );
  }
}
