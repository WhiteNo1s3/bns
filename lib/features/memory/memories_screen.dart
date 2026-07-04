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
  String _searchQuery = '';
  bool _loading = true;
  bool _showGarden = false; // visual garden for good memories

  final List<String> _predefinedTags = ['crisis', 'good', 'felt safe', 'felt confused', 'felt out of bound', 'drama', 'wonderings', 'routine'];

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    final all = await IsarService.getAllCaptures();
    // Only show remember or memorize levels
    var filtered = all.where((c) => c.memoryLevel != MemoryLevel.quick).toList();

    if (_filterLevel != null) {
      filtered = filtered.where((c) => c.memoryLevel == _filterLevel).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((c) {
        final textMatch = (c.text ?? '').toLowerCase().contains(q) || (c.contextNote ?? '').toLowerCase().contains(q);
        final tagMatch = c.tags.any((t) => t.toLowerCase().contains(q) || _predefinedTags.contains(t) && t.toLowerCase().contains(q));
        return textMatch || tagMatch;
      }).toList();
    }

    if (mounted) {
      setState(() {
        _memories = filtered;
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
          IconButton(
            icon: Icon(_showGarden ? Icons.list : Icons.local_florist),
            tooltip: _showGarden ? 'List view' : 'Memory Garden (good memories visual)',
            onPressed: () => setState(() => _showGarden = !_showGarden),
          ),
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
                // Warning for past - advise keep past in past, stay grounded (common for neuro damage to relive)
                if (_memories.any((m) => DateTime.now().difference(m.at).inDays > 7))
                  Container(
                    color: Colors.orange.shade100,
                    padding: const EdgeInsets.all(8),
                    child: const Text(
                      '⚠️ Entering past memories? We advise keeping the past in the past and moving forward. Stay on the ground. Don\'t react. It\'s common with neurological damage to relive stuff. Take care.',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Search for routine or crisis tag - organized for doctors, confidence "you made it"
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search routine, crisis, tag... (for doctors share, see your wins)',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _loadMemories();
                    },
                  ),
                ),
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
                      : _showGarden 
                        ? _buildGardenView() 
                        : ListView.builder(
                          itemCount: _memories.length,
                          itemBuilder: (ctx, i) {
                            final m = _memories[i];
                            final dateStr = DateFormat.yMMMd().format(m.at);
                            final isPast = DateTime.now().difference(m.at).inDays > 7;
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              color: isPast ? Colors.grey.shade100 : null,
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
                                    Text(dateStr + (isPast ? ' (past - take care)' : '')),
                                    if (m.contextNote != null) Text('Context: ${m.contextNote}', style: const TextStyle(fontStyle: FontStyle.italic)),
                                    if (m.linkedRoutineId != null) const Text('Linked to a routine'),
                                    if (m.tags.isNotEmpty) Text('Tags: ${m.tags.join(", ")}'),
                                  ],
                                ),
                                trailing: m.audioPath != null 
                                  ? IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () => _playAudio(m.audioPath),
                                    )
                                  : null,
                                onTap: () {
                                  if (isPast) {
                                    // Extra warning
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Past memory warning'),
                                        content: const Text('Stay on the ground and don\'t react. Keeping the past in the past helps move forward. It\'s common with neurological damage to relive. Consider if now is the right time.'),
                                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Understood'))],
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Memory from $dateStr. You made it through that day!')),
                                    );
                                  }
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

  Widget _buildGardenView() {
    // Visual memory garden: bright cards for good memories to make fogged users brighter
    // Garden = good memories (tags like good, felt safe)
    // Roots = ugly parts (crisis, drama, felt confused) - shown with caution, advise past in past
    final goodMemories = _memories.where((m) => m.tags.any((t) => ['good', 'felt safe'].contains(t.toLowerCase()))).toList();
    final rootMemories = _memories.where((m) => m.tags.any((t) => ['crisis', 'drama', 'felt confused', 'felt out of bound'].contains(t.toLowerCase()))).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('🌱 Memory Garden - Good memories (brighter for fogged minds)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Text('Click to celebrate what you made it through. Tags make it organized for doctors too.', style: TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          if (goodMemories.isEmpty)
            const Text('No good memories tagged yet. Use "good" or "felt safe" tags!')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: goodMemories.map((m) {
                final color = m.tags.contains('good') ? Colors.lightGreen : Colors.lightBlue;
                return InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You made it! ${m.text ?? m.contextNote ?? ""}')));
                  },
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.contextNote ?? m.text ?? 'Good memory', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(DateFormat.Md().format(m.at), style: const TextStyle(fontSize: 10, color: Colors.black54)),
                        if (m.tags.isNotEmpty) Text(m.tags.join(', '), style: const TextStyle(fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          const Text('🌿 Roots - The harder parts (Alzheimer, dementia, ADHD, ADD, mental illness, crises)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown)),
          const Text('These are the "ugly" neurological roots. We acknowledge them but advise: keep past in past, stay grounded. Use only if it helps move forward. Warning on tap.', style: TextStyle(fontSize: 10)),
          const SizedBox(height: 8),
          if (rootMemories.isEmpty)
            const Text('No root memories yet.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: rootMemories.map((m) {
                return InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Roots warning'),
                        content: const Text('Stay on the ground. Don\'t react or relive. It\'s common with neurological issues (TBI, ADHD, dementia etc.) to feel it again. Consider if helpful now. Past in the past, move forward.'),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
                      ),
                    );
                  },
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.brown.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.contextNote ?? m.text ?? 'Hard memory', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        Text(DateFormat.Md().format(m.at), style: const TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          const Text('Abstract mind tags (penguin, etc.): use custom tags in capture. We secure the penguin - no judgment on how you feel.', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }