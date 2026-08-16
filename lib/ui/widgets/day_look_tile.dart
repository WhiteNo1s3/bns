import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';

/// Look-only row for a day that has not come.
///
/// Name + time. No empty box. No Done. No didn\'t-happen. No pencil.
/// A tap may say the day has not come — that is a label, not an editor.
class DayLookTile extends StatelessWidget {
  final String title;
  final String? time;
  final VoidCallback? onTap;

  const DayLookTile({
    super.key,
    required this.title,
    this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final clock = (time ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minVerticalPadding: 12,
        title: Text(title, style: const TextStyle(fontSize: 17)),
        subtitle: clock.isEmpty
            ? null
            : Text(clock,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
        onTap: onTap,
      ),
    );
  }
}

/// Hebrew-first words for a tap on a day that has not started.
String dayHasNotComeLabel() =>
    L.t('The day has not come — it can wait for you.',
        'היום הזה עוד לא הגיע — הוא יחכה לך.');
