import 'package:flutter/material.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/data/local/isar_service.dart';
import 'package:bns/ui/widgets/bns_app_bar.dart';
import 'package:bns/features/capture/quick_capture_screen.dart';
import 'package:bns/services/audio_playback_service.dart';
import 'package:bns/services/tts_service.dart';
import 'package:intl/intl.dart';

/// Memory section: Remember this (contextual for routines/days/crises)
/// and Memorize this (permanent memories).
///
/// Captures what happened in routines, why, the day itself.
/// Not just reminders - the memory of the event/day is stored.
///
/// Permanent ones are protected from pruning.
///
/// User can remove memories (and other data).
/// Everything the user wants he can do.
/// Advise if sure (confirmation).
/// Deleted items go to trash, stay 3 days, then permanent delete.
/// .bns delivers full active data (memories included if not trashed).
/// Ties to routines: log "things that happened" during them.
class MemoriesScreen extends StatefulWidget {
  const MemoriesScreen({super.key});

  @override
  State<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends State<MemoriesScreen> {
  List<QuickCapture> _raw = []; // straight from the store (active OR trash)
  List<QuickCapture> _memories = []; // what's shown after filter + search
  MemoryLevel? _filterLevel;
  String _searchQuery = '';
  bool _loading = true;
  bool _showGarden = false; // visual garden for good memories
  bool _showTrash = false; // trash view: deleted items, 3 days then gone
  String _userType = 'normal';

  final List<String> _predefinedTags = [
    'crisis',
    'good',
    'felt safe',
    'felt confused',
    'felt out of bound',
    'drama',
    'wonderings',
    'routine'
  ];

  @override
  void initState() {
    super.initState();
    _loadUserType();
    _loadMemories();
  }

  Future<void> _loadUserType() async {
    final s = await IsarService.getSettings();
    if (mounted) setState(() => _userType = s.userType);
  }

  double get _textScale =>
      (_userType.contains('kid') || _userType == 'ADHD') ? 1.18 : 1.0;

  /// Hits the store — only when the underlying data can actually have
  /// changed (first open, trash toggle, delete/restore). Typing NEVER
  /// lands here: search and level filters run in memory via [_applyFilters],
  /// so there's no spinner flash and no disk read per key press.
  Future<void> _loadMemories() async {
    setState(() => _loading = true);
    final source = _showTrash
        ? await IsarService.getTrashedCaptures()
        : await IsarService.getAllCaptures();
    _raw = source.where((c) => c.memoryLevel != MemoryLevel.quick).toList();
    if (mounted) _applyFilters();
  }

  /// Pure in-memory filtering — synchronous, instant, no loading state.
  void _applyFilters() {
    var filtered = _raw;

    if (_filterLevel != null && !_showTrash) {
      filtered = filtered.where((c) => c.memoryLevel == _filterLevel).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((c) {
        final textMatch = (c.text ?? '').toLowerCase().contains(q) ||
            (c.transcript ?? '').toLowerCase().contains(q) ||
            (c.contextNote ?? '').toLowerCase().contains(q);
        final tagMatch = c.tags.any((t) =>
            t.toLowerCase().contains(q) ||
            _predefinedTags.contains(t) && t.toLowerCase().contains(q));
        return textMatch || tagMatch;
      }).toList();
    }

    setState(() {
      _memories = filtered;
      _loading = false;
    });
  }

  void _setFilter(MemoryLevel? level) {
    _filterLevel = level;
    _applyFilters();
  }

  Future<void> _playAudio(String? path) async {
    if (path == null) return;
    // Real playback — tap plays, tap again stops, a gone file says so.
    try {
      await AudioPlaybackService.toggle(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(L.t(
              'The sound for this one is not on this device anymore.',
              'הצליל של הזיכרון הזה כבר לא נמצא במכשיר הזה.'))));
    }
  }

  Future<void> _deleteMemory(QuickCapture mem) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L.t('Move to trash?', 'להעביר לאשפה?')),
        content: Text(L.t(
            'This will move "${mem.text ?? mem.transcript ?? mem.contextNote ?? 'memory'}" to trash. It will be permanently deleted after 3 days. You can restore from Trash.',
            'זה יעביר את "${mem.text ?? mem.transcript ?? mem.contextNote ?? 'זיכרון'}" לאשפה. אחרי 3 ימים המחיקה סופית. אפשר לשחזר מהאשפה.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(L.t('Cancel', 'ביטול'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L.t('Move to Trash', 'להעביר לאשפה')),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await IsarService.softDeleteCapture(mem.id);
      await _loadMemories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(L.t(
                  'Moved to trash. You can restore within 3 days.',
                  'הועבר לאשפה. אפשר לשחזר תוך 3 ימים.'))),
        );
      }
    }
  }

  Future<void> _restoreMemory(QuickCapture mem) async {
    await IsarService.restoreCapture(mem.id);
    await _loadMemories();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L.t('Restored from trash.', 'שוחזר מהאשפה.'))),
      );
    }
  }

  Widget _buildGardenView() {
    // Visual memory garden: bright cards for good memories to make fogged users brighter
    // Garden = good memories (tags like good, felt safe)
    // Roots = ugly parts (crisis, drama, felt confused) - shown with caution, advise past in past
    final goodMemories = _memories
        .where((m) =>
            m.tags.any((t) => ['good', 'felt safe'].contains(t.toLowerCase())))
        .toList();
    final rootMemories = _memories
        .where((m) => m.tags.any((t) => [
              'crisis',
              'drama',
              'felt confused',
              'felt out of bound'
            ].contains(t.toLowerCase())))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              L.t(
                  '🌱 Memory Garden - Good memories (brighter for fogged minds)',
                  '🌱 גינת הזיכרונות - זיכרונות טובים (בהירים יותר לראש מעורפל)'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Text(
              L.t(
                  'Click to celebrate what you made it through. Tags make it organized for doctors too.',
                  'הקשה כדי לחגוג את מה שעברת. התגיות שומרות על סדר גם מול רופאים.'),
              style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          if (goodMemories.isEmpty)
            Text(L.t(
                'No good memories tagged yet. Use "good" or "felt safe" tags!',
                'אין עדיין זיכרונות טובים עם תגית. אפשר להשתמש בתגיות "good" או "felt safe"!'))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: goodMemories.map((m) {
                final color = m.tags.contains('good')
                    ? Colors.lightGreen
                    : Colors.lightBlue;
                return InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(L.t(
                            'You made it! ${m.text ?? m.transcript ?? m.contextNote ?? ""}',
                            'עברת את זה! ${m.text ?? m.transcript ?? m.contextNote ?? ""}'))));
                  },
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black12, blurRadius: 4)
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            m.text ??
                                m.transcript ??
                                m.contextNote ??
                                L.t('A voice-only moment (no words yet)',
                                    'רגע קולי בלבד (עדיין בלי מילים)'),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(DateFormat.Md().format(m.at),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.black54)),
                        if (m.tags.isNotEmpty)
                          Text(m.tags.join(', '),
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.black54)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 24),
          Text(
              L.t(
                  '🌿 Roots - The harder parts (Alzheimer, dementia, ADHD, ADD, mental illness, crises)',
                  '🌿 שורשים - החלקים הקשים יותר (אלצהיימר, דמנציה, ADHD, ADD, קשיים נפשיים, משברים)'),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown)),
          Text(
              L.t(
                  'These are the "ugly" neurological roots. We acknowledge them but advise: keep past in past, stay grounded. Use only if it helps move forward. Warning on tap.',
                  'אלה השורשים הנוירולוגיים ה"מכוערים". אנחנו מכירים בהם, אבל ממליצים: להשאיר את העבר בעבר ולהישאר על הקרקע. להשתמש רק אם זה עוזר להתקדם. אזהרה בהקשה.'),
              style: const TextStyle(fontSize: 10)),
          const SizedBox(height: 8),
          if (rootMemories.isEmpty)
            Text(L.t('No root memories yet.', 'אין עדיין זיכרונות שורש.'))
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
                        title: Text(L.t('Roots warning', 'אזהרת שורשים')),
                        content: Text(L.t(
                            'Stay on the ground. Don\'t react or relive. It\'s common with neurological issues (TBI, ADHD, dementia etc.) to feel it again. Consider if helpful now. Past in the past, move forward.',
                            'להישאר על הקרקע. לא להגיב ולא לחיות את זה מחדש. עם קשיים נוירולוגיים (פגיעת ראש, ADHD, דמנציה ועוד) נפוץ להרגיש את זה שוב. כדאי לבדוק אם זה עוזר עכשיו. העבר בעבר, מתקדמים הלאה.')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(L.t('Got it', 'הבנתי')))
                        ],
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
                        Text(
                            m.text ??
                                m.transcript ??
                                m.contextNote ??
                                L.t('A voice-only moment (no words yet)',
                                    'רגע קולי בלבד (עדיין בלי מילים)'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11)),
                        Text(DateFormat.Md().format(m.at),
                            style: const TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
          Text(
              L.t(
                  'Abstract mind tags (penguin, etc.): use custom tags in capture. We secure the penguin - no judgment on how you feel.',
                  'תגיות של דמיון (פינגווין וכו׳): אפשר להשתמש בתגיות אישיות בתיעוד. אנחנו שומרים על הפינגווין - בלי שיפוט על איך שמרגישים.'),
              style: const TextStyle(fontSize: 10, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rememberCount =
        _memories.where((m) => m.memoryLevel == MemoryLevel.remember).length;
    final memorizeCount =
        _memories.where((m) => m.memoryLevel == MemoryLevel.memorize).length;

    return Scaffold(
      appBar: BnsAppBar(
        title: L.t('Memory Section', 'אזור הזיכרונות'),
        leading: Image.asset('assets/icon/bns_logo.png', height: 32, width: 32),
        hideOnDesktopWide: true,
        actions: [
          IconButton(
            icon:
                Icon(_showTrash ? Icons.delete_forever : Icons.delete_outline),
            tooltip: _showTrash
                ? L.t('Back to active memories', 'חזרה לזיכרונות הפעילים')
                : L.t('Trash (deleted, 3 days then gone)',
                    'אשפה (נמחקים, אחרי 3 ימים נעלמים)'),
            onPressed: () {
              setState(() => _showTrash = !_showTrash);
              _loadMemories();
            },
          ),
          IconButton(
            icon: Icon(_showGarden ? Icons.list : Icons.local_florist),
            tooltip: _showGarden
                ? L.t('List view', 'תצוגת רשימה')
                : L.t('Memory Garden (good memories visual)',
                    'גינת הזיכרונות (תצוגה של זיכרונות טובים)'),
            onPressed: () => setState(() => _showGarden = !_showGarden),
          ),
          PopupMenuButton<MemoryLevel?>(
            icon: const Icon(Icons.filter_list),
            onSelected: _setFilter,
            itemBuilder: (ctx) => [
              PopupMenuItem(
                  value: null,
                  child: Text(L.t('All memories', 'כל הזיכרונות'))),
              PopupMenuItem(
                  value: MemoryLevel.remember,
                  child: Text(L.t('Remember this (contextual)',
                      'לזכור את זה (עם הקשר)'))),
              PopupMenuItem(
                  value: MemoryLevel.memorize,
                  child: Text(L.t('Memorize permanently', 'לשמור לתמיד'))),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Warning for past - advise keep past in past, stay grounded (common for neuro damage to relive)
                if (_memories
                    .any((m) => DateTime.now().difference(m.at).inDays > 7))
                  Container(
                    color: Colors.orange.shade100,
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      L.t(
                          '⚠️ Entering past memories? We advise keeping the past in the past and moving forward. Stay on the ground. Don\'t react. It\'s common with neurological damage to relive stuff. Take care.',
                          '⚠️ נכנסים לזיכרונות מהעבר? אנחנו ממליצים להשאיר את העבר בעבר ולהתקדם. להישאר על הקרקע. לא להגיב. עם פגיעה נוירולוגית נפוץ לחיות דברים מחדש. לשמור על עצמך.'),
                      style: const TextStyle(color: Colors.black87, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                // Search for routine or crisis tag - organized for doctors, confidence "you made it"
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: L.t('Search your memories…', 'חיפוש בזיכרונות שלך…'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      // In-memory only — typing must never flash a spinner
                      // or touch the disk (it felt like the UI "refreshing"
                      // on every key press).
                      _searchQuery = val;
                      _applyFilters();
                    },
                  ),
                ),
                // Summary - crisp overview
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _MemoryStat(L.t('Remember this', 'לזכור את זה'),
                          rememberCount, MemoryLevel.remember),
                      _MemoryStat(L.t('Memorize this', 'לשמור לתמיד'),
                          memorizeCount, MemoryLevel.memorize),
                    ],
                  ),
                ),
                if (_userType != 'normal')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _userType.contains('kid')
                          ? L.t('🌟 Big bright garden for you! Click to celebrate.',
                              '🌟 גינה גדולה ומאירה בשבילך! הקשה כדי לחגוג.')
                          : L.t('Adapted view for your mind — you got this.',
                              'תצוגה מותאמת בשבילך — יש לך את זה.'),
                      style: TextStyle(
                          fontSize: 12 * _textScale,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                const Divider(),
                Expanded(
                  child: _memories.isEmpty
                      ? Center(
                          child: Text(
                            _showTrash
                                ? L.t(
                                    'Trash is empty. Deleted items stay here for 3 days.',
                                    'האשפה ריקה. פריטים שנמחקו נשארים כאן 3 ימים.')
                                : L.t(
                                    'No memories yet.\nUse "Remember this" in routines or capture to log what happened.',
                                    'אין עדיין זיכרונות.\nאפשר להשתמש ב"לזכור את זה" בשגרות או בתיעוד כדי לרשום מה קרה.'),
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
                                final isPast =
                                    DateTime.now().difference(m.at).inDays > 7;
                                // Words are always there: typed text, or what
                                // the device engine heard, or the context.
                                final words = (m.text ??
                                        m.transcript ??
                                        m.contextNote ??
                                        '')
                                    .trim();
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 6),
                                  // Past = a quieter shade of the SAME theme.
                                  // A hardcoded light grey here painted white
                                  // dark-mode text on a light card — every
                                  // memory older than a week was unreadable
                                  // on the PC (owner QA, 2026-08-09).
                                  color: isPast
                                      ? Theme.of(ctx)
                                          .colorScheme
                                          .surfaceContainerHighest
                                      : null,
                                  child: ListTile(
                                    leading: Icon(
                                      m.memoryLevel == MemoryLevel.memorize
                                          ? Icons.stars
                                          : Icons.bookmark,
                                      color:
                                          m.memoryLevel == MemoryLevel.memorize
                                              ? Colors.amber
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                    ),
                                    title: Text(words.isEmpty
                                        ? L.t(
                                            'A voice-only moment (no words yet)',
                                            'רגע קולי בלבד (עדיין בלי מילים)')
                                        : words),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(dateStr +
                                            (isPast
                                                ? L.t(' (past - take care)',
                                                    ' (עבר - בעדינות)')
                                                : '')),
                                        if (m.contextNote != null)
                                          Text(
                                              L.t('Context: ${m.contextNote}',
                                                  'הקשר: ${m.contextNote}'),
                                              style: const TextStyle(
                                                  fontStyle: FontStyle.italic)),
                                        if (m.linkedRoutineId != null)
                                          Text(L.t('Linked to a routine',
                                              'מקושר לשגרה')),
                                        if (m.tags.isNotEmpty)
                                          Text(L.t('Tags: ${m.tags.join(", ")}',
                                              'תגיות: ${m.tags.join(", ")}')),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // The app reads the kept words aloud
                                        // — default manner, relaxed.
                                        if (words.isNotEmpty)
                                          IconButton(
                                            tooltip: L.t('Hear it read aloud',
                                                'להקריא בקול'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32),
                                            iconSize: 20,
                                            icon: const Icon(Icons.volume_up),
                                            onPressed: () =>
                                                TtsService.speak(words),
                                          ),
                                        if (m.audioPath != null)
                                          IconButton(
                                            icon: const Icon(Icons.play_arrow),
                                            onPressed: () =>
                                                _playAudio(m.audioPath),
                                          ),
                                        if (_showTrash)
                                          IconButton(
                                            icon: const Icon(Icons.restore),
                                            onPressed: () => _restoreMemory(m),
                                            tooltip: L.t('Restore', 'שחזור'),
                                          )
                                        else
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline),
                                            onPressed: () => _deleteMemory(m),
                                            tooltip: L.t('Move to trash',
                                                'העברה לאשפה'),
                                          ),
                                      ],
                                    ),
                                    onTap: () {
                                      if (isPast) {
                                        // Extra warning
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: Text(L.t(
                                                'Past memory warning',
                                                'אזהרת זיכרון מהעבר')),
                                            content: Text(L.t(
                                                'Stay on the ground and don\'t react. Keeping the past in the past helps move forward. It\'s common with neurological damage to relive. Consider if now is the right time.',
                                                'להישאר על הקרקע ולא להגיב. להשאיר את העבר בעבר עוזר להתקדם. עם פגיעה נוירולוגית נפוץ לחיות דברים מחדש. כדאי לבדוק אם זה הזמן הנכון.')),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: Text(L.t(
                                                      'Understood', 'הבנתי')))
                                            ],
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(L.t(
                                                  'Memory from $dateStr. You made it through that day!',
                                                  'זיכרון מ־$dateStr. עברת את היום ההוא!'))),
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
        label: Text(L.t('Capture memory', 'תיעוד זיכרון')),
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
        Text('$count',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
