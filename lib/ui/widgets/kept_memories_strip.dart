import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/features/memory/memory_view_screen.dart';

/// The last few kept thoughts, on Today — so a recording is not a
/// disappearing trick. Tap opens that memory.
class KeptMemoriesStrip extends StatelessWidget {
  final List<QuickCapture> memories;

  const KeptMemoriesStrip({super.key, required this.memories});

  @override
  Widget build(BuildContext context) {
    if (memories.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          L.t('What you kept', 'מה ששמרת'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final m in memories)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Icon(
                m.audioPath != null ? Icons.mic : Icons.bookmark_border,
                color: cs.primary,
              ),
              title: Text(
                memoryWords(m).isEmpty
                    ? L.t('A voice moment', 'רגע קולי')
                    : memoryWords(m),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, height: 1.3),
              ),
              subtitle: Text(
                DateFormat.MMMd(L.isHebrew ? 'he' : 'en').add_Hm().format(m.at),
              ),
              trailing: const Icon(Icons.chevron_right, matchTextDirection: true),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MemoryViewScreen(memory: m)),
              ),
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => context.go('/memories'),
            child: Text(L.t('All your memories', 'כל הזיכרונות שלך')),
          ),
        ),
      ],
    );
  }
}
