/// When a device asks to pair, should the person see EnterCodeDialog?
///
/// Owner / L2 (2026-08-17): pairing is app-wide and used to sit on בוצע.
/// A friend already in the file stays quiet — deaf sync is not a reason
/// to re-pair. Completing a plan or routine finishes first; a connect
/// prompt waits. A leftover extra copy must not stack a second sheet.
library;

import 'dart:async';

/// What to do with an incoming PAIR ask.
enum PairAskDisposition {
  /// Already trusted, or another sheet is already up. No dialog.
  stayQuiet,

  /// Someone is marking done / skip. Hold the ask until that finishes.
  waitForDone,

  /// A truly new device, and Done is idle. Show the dismissible sheet.
  prompt,
}

/// Pure. Trusted wins over everything — even mid-Done, stay quiet.
PairAskDisposition pairAskDisposition({
  required bool alreadyTrusted,
  required bool completing,
  bool promptAlreadyOpen = false,
}) {
  if (alreadyTrusted) return PairAskDisposition.stayQuiet;
  if (completing) return PairAskDisposition.waitForDone;
  if (promptAlreadyOpen) return PairAskDisposition.stayQuiet;
  return PairAskDisposition.prompt;
}

/// Latch so a PAIR ask cannot steal בוצע / the miss sheet.
///
/// Done and skip call [begin] / [end] (or [run]). The pairing handler
/// [waitUntilIdle]s before it may show EnterCodeDialog.
class PairingGate {
  static final PairingGate instance = PairingGate();

  int _completing = 0;
  int _prompting = 0;
  final List<Completer<void>> _waiters = [];

  bool get isCompleting => _completing > 0;
  bool get isPrompting => _prompting > 0;

  void begin() => _completing++;

  void end() {
    if (_completing > 0) _completing--;
    if (_completing == 0) {
      for (final w in _waiters) {
        if (!w.isCompleted) w.complete();
      }
      _waiters.clear();
    }
  }

  Future<T> run<T>(Future<T> Function() work) async {
    begin();
    try {
      return await work();
    } finally {
      end();
    }
  }

  Future<void> waitUntilIdle() async {
    if (_completing == 0) return;
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  /// One sheet at a time. A leftover extra copy returns null.
  Future<T?> runPrompt<T>(Future<T?> Function() show) async {
    if (_prompting > 0) return null;
    _prompting++;
    try {
      return await show();
    } finally {
      _prompting--;
    }
  }
}
