import 'package:flutter/material.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:intl/intl.dart';

/// Memory section: Remember this (contextual for routines/days/crises) 
/// and Memorize this (permanent memories).
/// 
/// Captures what happened in routines, why, the day itself.
/// Not just reminders - the memory of the event/day is stored.
/// 
/// Permanent ones are protected from pruning.
/// Ties to routines: log "things that happened" during them.
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<QuickCapture> _memories = [];
  MemoryLevel? _filterLevel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    final all = await IsarService.getAllCaptures();
    // Only show remember or memorize levels
    final filtered = all.where((c) => c.memoryLevel != MemoryLevel.quick).toList();
    if (mounted) {
      setState(() {
        _memories = _filterLevel == null 
          ? filtered 
          : filtered.where((c) => c.memoryLevel == _filterLevel).toList();
        _loading = false;
      });
    }
  }

  void _setFilter(MemoryLevel? level) {
    setState(() => _filterLevel = level);
    _loadMemories();
  }

  Future<void> _playAudio(String? path) async {
    if (path == null) return;
    // Reuse simple player or snack for now
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playing memory audio: ${path.split('/').last}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rememberCount = _memories.where((m) => m.memoryLevel == MemoryLevel.remember).length;
    final memorizeCount = _memories.where((m) => m.memoryLevel == MemoryLevel.memorize).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory Section'),
        actions: [
          PopupMenuButton<MemoryLevel?>(
            icon: const Icon(Icons.filter_list),
            onSelected: _setFilter,
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: null, child: Text('All memories')),
              const PopupMenuItem(value: MemoryLevel.remember, child: Text('Remember this (contextual)')),
              const PopupMenuItem(value: MemoryLevel.memorize, child: Text('Memorize permanently')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary - crisp overview
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MemoryStat('Remember this', rememberCount, MemoryLevel.remember),
                      _MemoryStat('Memorize this', memorizeCount, MemoryLevel.memorize),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _memories.isEmpty
                      ? const Center(
                          child: Text(
                            'No memories yet.\nUse "Remember this" in routines or capture to log what happened.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _memories.length,
                          itemBuilder: (ctx, i) {
                            final m = _memories[i];
                            final dateStr = DateFormat.yMMMd().format(m.at);
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: ListTile(
                                leading: Icon(
                                  m.memoryLevel == MemoryLevel.memorize 
                                    ? Icons.stars 
                                    : Icons.bookmark,
                                  color: m.memoryLevel == MemoryLevel.memorize 
                                    ? Colors.amber 
                                    : Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(m.text ?? m.contextNote ?? 'Memory captured'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(dateStr),
                                    if (m.contextNote != null) Text('Context: ${m.contextNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
                                    if (m.linkedRoutineId != null) const Text('Linked to a routine'),
                                  ],
                                ),
                                trailing: m.audioPath != null 
                                  ? IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () => _playAudio(m.audioPath),
                                    )
                                  : null,
                                onTap: () {
                                  // Could open detail or edit
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Memory from $dateStr. Day remembered.')),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Open capture pre-set to remember or memorize
          final saved = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const QuickCaptureScreen(
                // Could pass initial for memorize
              ),
            ),
          );
          if (saved == true) _loadMemories();
        },
        icon: const Icon(Icons.add),
        label: const Text('Capture memory'),
      ),
    );
  }
}

class _MemoryStat extends StatelessWidget {
  final String label;
  final int count;
  final MemoryLevel level;

  const _MemoryStat(this.label, this.count, this.level);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}