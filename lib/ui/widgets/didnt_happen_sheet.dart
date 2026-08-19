import 'package:flutter/material.dart';

import 'package:bns/core/didnt_happen.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/ui/widgets/dictation_mic_button.dart';

/// Holds the typed why so Close / tap-out can still read it after the
/// sheet (and its controller) are gone.
class _ReasonHold {
  String text;
  _ReasonHold(this.text);
}

/// The one miss / skip door.
///
/// Type or speak why on THIS sheet. Close / tap-out with words logs the
/// skip. Empty close just closes. Confirm («זה לא קרה היום») always
/// skips. The confirm door sits above the keyboard. Voice stays in-sheet
/// — nobody is sent to capture to keep the why.
class _DidntHappenSheet extends StatefulWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final String initialReason;
  final _ReasonHold hold;

  const _DidntHappenSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.hold,
    this.initialReason = '',
  });

  @override
  State<_DidntHappenSheet> createState() => _DidntHappenSheetState();
}

class _DidntHappenSheetState extends State<_DidntHappenSheet> {
  late final TextEditingController _ctrl;

  /// True while a spoken why is still being written — the doors wait.
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialReason);
    _ctrl.addListener(() => widget.hold.text = _ctrl.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// THE SKIP-WHY THAT WENT BLANK: the ear writes words a moment AFTER
  /// the stop-press — a confirm that outran it kept an empty why, and a
  /// confirm mid-take CANCELLED the recording, so the spoken why died
  /// with the sheet. Both worded doors now settle the mic first: the
  /// take is finished, the words land in the field, and only then does
  /// the sheet answer with everything that was said.
  Future<void> _finish(
      DidntHappenResult Function(String words) result) async {
    if (_settling) return; // one press is already doing the whole job
    setState(() => _settling = true);
    await DictationMicButton.settle(_ctrl);
    if (!mounted) return;
    Navigator.pop(context, result(_ctrl.text));
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 16 + keyboard),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(widget.body),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              minLines: 1,
              autofocus: true,
              decoration: InputDecoration(
                hintText: L.t(
                    'What got in the way? (tap the mic to speak)',
                    'מה הפריע? (הקשה על המיקרופון כדי לדבר)'),
                border: const OutlineInputBorder(),
                suffixIcon: DictationMicButton(controller: _ctrl),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => _finish(didntHappenOnConfirm),
              child: _settling
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(L.t('Writing the words…', 'כותבים את המילים…')),
                      ],
                    )
                  : Text(widget.confirmLabel),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: () => _finish(didntHappenOnDismiss),
                child: Text(L.t('Close', 'סגירה')),
              ),
            ),
          ],
      ),
    );
  }
}

/// Opens the miss sheet. Barrier / back with typed words still skip.
Future<DidntHappenResult> showDidntHappenSheet({
  required BuildContext context,
  required String title,
  String? body,
  required String confirmLabel,
  String initialReason = '',
}) async {
  final hold = _ReasonHold(initialReason);
  final popped = await showModalBottomSheet<DidntHappenResult>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _DidntHappenSheet(
      title: title,
      // Adult temperature (the law quotes this very sheet: «לא קרה —
      // נרשם» beats «זה בסדר גמור») — and a deliberate skip is a
      // decision, and deciding counts. Say that, skip the hug.
      body: body ??
          L.t(
              'Didn\'t happen — deciding that counts too. If something got '
              'in the way, you can write it here — it is kept so it can help.',
              'לא קרה — גם להחליט את זה נחשב. אם משהו הפריע, אפשר לכתוב '
              'כאן — זה נשמר כדי שיהיה אפשר לעזור.'),
      confirmLabel: confirmLabel,
      initialReason: initialReason,
      hold: hold,
    ),
  );
  if (popped != null) return popped;
  // Tap-out / system back — same Close rule. [hold] still has the words.
  return didntHappenOnDismiss(hold.text);
}
