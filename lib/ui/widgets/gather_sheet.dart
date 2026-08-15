/// "מה לוקחים?" — WHAT DO WE TAKE.
///
/// Owner design, 2026-08-15, from rehabilitation at Shiba: a person who
/// cannot gather a single item themselves is STILL asked "did we take X?
/// did we take Y?" — and the answering is the part they play. The people
/// there treat the person, not only the caregiver; they hand over what
/// they know and a role to hold, instead of handling someone like a doll.
///
/// So this screen is built around one rule:
///
///   THE PERSON ANSWERS. Someone else may carry the bag.
///
/// Everything follows from it:
///   - The voice is WE ("לקחנו את זה"), never "did you remember" — the
///     helper and the person are doing this together, and a question in
///     the plural cannot become an accusation.
///   - Answering is possible at EVERY care level, including level 4.
///     Building the list is what gets locked to the helper — never the
///     answering, because the answering is the dignity.
///   - "Not yet" is a state, not a failure: no red, no counter of misses.
///     Taking something back off the list is one tap, always.
library;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/services/haptics.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';

/// Opens the gather sheet for [plan]. [onChanged] receives the updated
/// list whenever the person answers or the helper edits.
///
/// [canEdit] false = level 4: the person answers, the helper builds.
Future<void> showGatherSheet({
  required BuildContext context,
  required CalendarEvent plan,
  required bool canEdit,
  required Future<void> Function(List<GatherItem>) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _GatherSheet(
      plan: plan,
      canEdit: canEdit,
      onChanged: onChanged,
    ),
  );
}

class _GatherSheet extends StatefulWidget {
  final CalendarEvent plan;
  final bool canEdit;
  final Future<void> Function(List<GatherItem>) onChanged;

  const _GatherSheet({
    required this.plan,
    required this.canEdit,
    required this.onChanged,
  });

  @override
  State<_GatherSheet> createState() => _GatherSheetState();
}

class _GatherSheetState extends State<_GatherSheet> {
  static const _uuid = Uuid();
  late List<GatherItem> _items;
  final _addController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _items = List<GatherItem>.from(widget.plan.gather);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  Future<void> _push() => widget.onChanged(List<GatherItem>.from(_items));

  /// The answer itself. A buzz lands with it so the hand knows it counted
  /// even if the eyes are slow to find the ✓.
  Future<void> _answer(GatherItem item) async {
    BnsHaptics.tick();
    final i = _items.indexWhere((g) => g.id == item.id);
    if (i < 0) return;
    setState(() {
      _items[i] = item.taken
          ? item.copyWith(takenAt: null)
          : item.copyWith(takenAt: DateTime.now());
    });
    await _push();
  }

  Future<void> _add() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _items.add(GatherItem(id: _uuid.v4(), text: text));
      _addController.clear();
    });
    await _push();
  }

  Future<void> _remove(GatherItem item) async {
    setState(() => _items.removeWhere((g) => g.id == item.id));
    await _push();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _items.isNotEmpty && _items.every((g) => g.taken);
    final taken = _items.where((g) => g.taken).length;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                L.t('What do we take for: ${widget.plan.title}',
                    'מה לוקחים ל: ${widget.plan.title}'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _items.isEmpty
                    ? L.t(
                        'Nothing on the list yet. Whatever should come along '
                            'can be written here — tonight, calmly, so tomorrow '
                            'only has to be answered.',
                        'עוד אין כלום ברשימה. אפשר לכתוב כאן כל מה שצריך לבוא '
                            'איתנו — הערב, ברוגע, כדי שמחר רק נצטרך לענות.')
                    : ready
                        ? L.t('Everything is with us. Ready to go. 🌿',
                            'הכול איתנו. אפשר לצאת. 🌿')
                        : L.t(
                            'Go through them together — "did we take this?" '
                                '$taken of ${_items.length} are with us.',
                            'עוברים על זה ביחד — ״לקחנו את זה?״ '
                                '$taken מתוך ${_items.length} כבר איתנו.'),
                style: TextStyle(fontSize: 15, height: 1.35, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),

              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final item in _items)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        color: item.taken
                            ? cs.primaryContainer.withValues(alpha: 0.55)
                            : null,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _answer(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                // A big, unmissable answer target — the
                                // whole row works, not just the box.
                                IgnorePointer(
                                  child: Transform.scale(
                                    scale: 1.3,
                                    child: Checkbox(
                                      value: item.taken,
                                      onChanged: (_) {},
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    item.text,
                                    style: TextStyle(
                                      fontSize: 18,
                                      height: 1.3,
                                      color: item.taken
                                          ? cs.onPrimaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                                if (widget.canEdit)
                                  IconButton(
                                    tooltip: L.t('Take off the list',
                                        'להוריד מהרשימה'),
                                    constraints: const BoxConstraints(
                                        minWidth: 48, minHeight: 48),
                                    icon: const Icon(Icons.close, size: 22),
                                    onPressed: () => _remove(item),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Building the list is the helper's job at level 4 — the
              // ANSWERING above never is.
              if (widget.canEdit) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _addController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: L.t('Something to take along…',
                        'עוד משהו שצריך לקחת…'),
                    border: const OutlineInputBorder(),
                    suffixIcon: DictationMicButton(controller: _addController),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 24),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  label: Text(L.t('Add it to the list', 'להוסיף לרשימה')),
                ),
              ],

              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(L.t('Close', 'סגירה')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
