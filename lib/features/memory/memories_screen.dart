import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/kept_memory.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/features/memory/memory_view_screen.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';

/// The person's kept thoughts — every recording and note they saved.
///
/// Law: if they recorded it, they see it. Levels do not hide anything.
/// Mad-vents stay out (sacred). Tap opens the memory itself.
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<QuickCapture> _raw = [];
  List<QuickCapture> _shown = [];
  String _search = '';
  bool _loading = true;
  bool _showTrash = false;
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _load();
    IsarService.dataRevision.addListener(_onData);
  }

  @override
  void dispose() {
    IsarService.dataRevision.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final source = _showTrash
        ? await IsarService.getTrashedCaptures()
        : await IsarService.getAllCaptures();
    // Trash shows everything that was put away. Living list follows
    // the visibility law — including quick notes.
    _raw = _showTrash
        ? List<QuickCapture>.from(source)
        : visibleMemories(source);
    if (mounted) _apply();
  }

  void _apply() {
    var list = _raw;
    final q = _search.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) {
        final words = memoryWords(c).toLowerCase();
        final tags = c.tags.join(' ').toLowerCase();
        return words.contains(q) || tags.contains(q);
      }).toList();
    }
    setState(() {
      _shown = list;
      _loading = false;
    });
  }

  Future<void> _open(QuickCapture m) async {
    if (_showTrash) {
      await IsarService.restoreCapture(m.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L.t('Brought back.', 'חזר.')),
        duration: const Duration(seconds: 2),
      ));
      await _load();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemoryViewScreen(memory: m)),
    );
    if (mounted) await _load();
  }

  Future<void> _restore(QuickCapture m) async {
    await IsarService.restoreCapture(m.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: BnsAppBar(
        title: _showTrash
            ? L.t('Put away', 'הונחו בצד')
            : L.t('Your memories', 'הזיכרונות שלך'),
        leading: Image.asset('assets/icon/bns_logo.png', height: 32, width: 32),
        hideOnDesktopWide: true,
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: L.t('Find', 'למצוא'),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _search = '';
                _apply();
              }
            }),
          ),
          IconButton(
            icon: Icon(_showTrash ? Icons.menu_book : Icons.delete_outline),
            tooltip: _showTrash
                ? L.t('Back to your memories', 'חזרה לזיכרונות שלך')
                : L.t('Things put away', 'דברים שהונחו בצד'),
            onPressed: () {
              setState(() {
                _showTrash = !_showTrash;
                _loading = true;
              });
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_showSearch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: L.t('Find a memory…', 'למצוא זיכרון…'),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        _search = val;
                        _apply();
                      },
                    ),
                  ),
                Expanded(
                  child: _shown.isEmpty
                      ? _EmptyMemories(
                          trash: _showTrash,
                          onTell: () => context.go('/capture'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: _shown.length,
                          itemBuilder: (ctx, i) {
                            final m = _shown[i];
                            final words = memoryWords(m);
                            final when = DateFormat.yMMMd(L.isHebrew ? 'he' : 'en')
                                .add_Hm()
                                .format(m.at);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                leading: Icon(
                                  m.audioPath != null
                                      ? Icons.mic
                                      : (m.memoryLevel == MemoryLevel.memorize
                                          ? Icons.star
                                          : Icons.bookmark_border),
                                  color: cs.primary,
                                  size: 28,
                                ),
                                title: Text(
                                  words.isEmpty
                                      ? L.t('A voice moment', 'רגע קולי')
                                      : words,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17, height: 1.3),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(when),
                                ),
                                trailing: _showTrash
                                    ? IconButton(
                                        icon: const Icon(Icons.restore),
                                        tooltip: L.t('Bring back', 'להחזיר'),
                                        onPressed: () => _restore(m),
                                      )
                                    : const Icon(Icons.chevron_right),
                                onTap: () => _open(m),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _showTrash
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/capture'),
              icon: const Icon(Icons.mic),
              label: Text(L.t('Keep this', 'לשמור את זה')),
            ),
    );
  }
}

class _EmptyMemories extends StatelessWidget {
  final bool trash;
  final VoidCallback onTell;

  const _EmptyMemories({required this.trash, required this.onTell});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              trash
                  ? L.t(
                      'Nothing waiting here. Things stay 3 days, then they rest.',
                      'אין כאן כלום שמחכה. דברים נשארים 3 ימים, ואז הם נחים.')
                  : L.t(
                      'Nothing kept yet. When you tell something, it will live here.',
                      'עוד לא נשמר כלום. כשתספרו משהו, הוא יחיה כאן.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, height: 1.4),
            ),
            if (!trash) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onTell,
                icon: const Icon(Icons.mic),
                label: Text(L.t('Keep something', 'לשמור משהו')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
