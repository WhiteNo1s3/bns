import 'package:flutter/material.dart';

import 'package:bns/core/i18n/l.dart';
import 'package:bns/services/whisper_ear.dart';

/// THE OFFER, ONCE (owner, 2026-08-19: "we should push into this as the new
/// standard").
///
/// The ear that belongs to this device is the standard now — but a standard
/// nobody is told about is just a setting nobody opens. So the room where
/// people actually speak says it once, quietly, where the mic is: one
/// download and the words stop depending on anyone else.
///
/// It never nags. «לא עכשיו» is remembered on this device forever, the
/// borrowed ear keeps working meanwhile, and the line disappears the moment
/// the ear is installed — from Settings or from here.
class OfflineEarOffer extends StatefulWidget {
  /// Called when the ear becomes available, so the room can refresh
  /// anything that depends on having an ear at all.
  final VoidCallback? onInstalled;

  const OfflineEarOffer({super.key, this.onInstalled});

  @override
  State<OfflineEarOffer> createState() => _OfflineEarOfferState();
}

class _OfflineEarOfferState extends State<OfflineEarOffer> {
  bool _show = false;
  bool _busy = false;
  double _progress = 0;
  String? _trouble;

  @override
  void initState() {
    super.initState();
    _ask();
  }

  Future<void> _ask() async {
    final show =
        WhisperEar.isSupportedPlatform &&
        !await WhisperEar.isInstalled() &&
        !await WhisperEar.offerDeclined();
    if (mounted) setState(() => _show = show);
  }

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _trouble = null;
    });
    try {
      await WhisperEar.install(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _show = false;
      });
      widget.onInstalled?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _trouble = L.t(
          'Could not fetch it right now — the words still get written the '
              'usual way.',
          'לא הצלחנו להוריד כרגע — המילים עדיין נכתבות כרגיל.',
        );
      });
    }
  }

  Future<void> _notNow() async {
    await WhisperEar.declineOffer();
    if (mounted) setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            L.t(
              'An ear of our own — no network, nobody in the middle',
              'אוזן משלנו — בלי רשת, בלי אף אחד באמצע',
            ),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            _busy
                ? L.t(
                    'Fetching it… ${(_progress * 100).round()}%',
                    'מורידים… ${(_progress * 100).round()}%',
                  )
                : _trouble ??
                      L.t(
                        'One 190 MB download. After it, recordings become '
                            'words on this device — offline, and nothing is left '
                            'out of what was said.',
                        'הורדה אחת של 190 מגה. אחרי זה ההקלטות הופכות למילים '
                            'במכשיר הזה — בלי רשת, ובלי שמשמיטים משהו ממה שנאמר.',
                      ),
            style: const TextStyle(fontSize: 13),
          ),
          if (_busy) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          ] else ...[
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: _install,
                  child: Text(L.t('Install', 'להתקין')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _notNow,
                  child: Text(L.t('Not now', 'לא עכשיו')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
