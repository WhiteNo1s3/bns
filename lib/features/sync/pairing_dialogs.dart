import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/data/sync/lan_sync_service.dart' show PairingResult;

/// Initiator side of pairing, in ONE step: the moment this dialog opens the
/// request is already on its way, so the other device asks for the code
/// while the person is looking at it here. No "I typed it there" button —
/// that button claimed the typing already happened before the other device
/// had even been asked (owner, 2026-08-09: "the button is deceptive").
class ShowCodeDialog extends StatefulWidget {
  final String peerName;

  /// A fresh 6-digit code for each attempt.
  final String Function() generateCode;

  /// Sends the PAIR request and waits for the other side's answer.
  final Future<PairingResult> Function(String code) sendRequest;

  const ShowCodeDialog({
    super.key,
    required this.peerName,
    required this.generateCode,
    required this.sendRequest,
  });

  @override
  State<ShowCodeDialog> createState() => _ShowCodeDialogState();
}

class _ShowCodeDialogState extends State<ShowCodeDialog> {
  late String _code;
  bool _waiting = true;
  PairingResult? _failure;

  @override
  void initState() {
    super.initState();
    _attempt();
  }

  Future<void> _attempt() async {
    _code = widget.generateCode();
    setState(() {
      _waiting = true;
      _failure = null;
    });
    final result = await widget.sendRequest(_code);
    if (!mounted) return;
    if (result == PairingResult.accepted) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _waiting = false;
        _failure = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.t('Connect to ${widget.peerName}',
          'התחברות אל ${widget.peerName}')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_waiting) ...[
            Text(
              L.t(
                  'Type this code on ${widget.peerName} — a small window is '
                  'asking for it there right now. (If nothing appeared, open '
                  'the Sync screen on that device.)',
                  'הקלד את הקוד הזה במכשיר ${widget.peerName} — חלון קטן '
                  'מבקש אותו שם ממש עכשיו. (אם שום דבר לא הופיע, פתח שם '
                  'את מסך הסנכרון.)'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              _code,
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(L.t('Waiting for the code to be typed there...',
                    'ממתינים שהקוד יוקלד שם...')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              L.t(
                  'The code never leaves this screen — only someone who can '
                  'read it here can pair.',
                  'הקוד לא עוזב את המסך הזה — רק מי שיכול לקרוא אותו כאן '
                  'יכול לצמד.'),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Icon(Icons.info_outline,
                size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              _failure == PairingResult.unreachable
                  ? L.t(
                      'Couldn\'t reach ${widget.peerName}. Make sure both '
                      'devices are on the same Wi-Fi and the app is open '
                      'there.',
                      'לא הצלחנו להגיע אל ${widget.peerName}. ודאו ששני '
                      'המכשירים באותו Wi-Fi ושהאפליקציה פתוחה שם.')
                  : L.t(
                      'No answer this time — the request was declined, or '
                      'the Sync screen wasn\'t open on ${widget.peerName}. '
                      'Open it there and try again.',
                      'לא התקבלה תשובה הפעם — הבקשה נדחתה, או שמסך '
                      'הסנכרון לא היה פתוח במכשיר ${widget.peerName}. '
                      'פתח אותו שם ונסה שוב.'),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_waiting
              ? L.t('Cancel', 'ביטול')
              : L.t('Not now', 'לא עכשיו')),
        ),
        if (!_waiting)
          FilledButton(
            onPressed: _attempt,
            child: Text(L.t('Try again (fresh code)', 'נסה שוב (קוד טרי)')),
          ),
      ],
    );
  }
}

/// Receiver side of pairing: type the 6-digit code shown on the other
/// device. Installed app-wide (main.dart), so the request reaches the
/// person on any screen — not only while the Sync screen happens to be open.
/// The one door for asking the person about a PAIR request — returns the
/// typed code, or null when they declined. Everything that shows this
/// dialog goes through here, so the gate logic in main stays honest.
Future<String?> showEnterCodeDialog({
  required BuildContext context,
  required String peerName,
}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EnterCodeDialog(peerName: peerName),
    );

class EnterCodeDialog extends StatefulWidget {
  final String peerName;

  const EnterCodeDialog({super.key, required this.peerName});

  @override
  State<EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<EnterCodeDialog> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L.t('"${widget.peerName}" wants to pair',
          '"${widget.peerName}" רוצה להתחבר')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(L.t(
              'Enter the 6-digit code shown on that device. If you didn\'t '
              'expect this, just decline — nothing is shared.',
              'הקלד את הקוד בן 6 הספרות שמוצג במכשיר השני. אם לא ציפית '
              'לזה, פשוט סרב — שום דבר לא משותף.')),
          const SizedBox(height: 16),
          TextField(
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            style: const TextStyle(fontSize: 28, letterSpacing: 8),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(L.t('Decline', 'סרב')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _codeController.text.trim()),
          child: Text(L.t('Pair securely', 'צמד באופן מאובטח')),
        ),
      ],
    );
  }
}
