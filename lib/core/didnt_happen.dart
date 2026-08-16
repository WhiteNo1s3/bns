/// One law for every "didn't happen" door.
///
/// If they wrote why, those words are the skip. Close / tap-out / back
/// with a non-empty reason logs the skip — same as the confirm door.
/// Empty close is just close. Never force them. Never swallow the why
/// into a second capture screen.
library;

class DidntHappenResult {
  final bool skipped;
  final String? reason;

  const DidntHappenResult.closed()
      : skipped = false,
        reason = null;

  const DidntHappenResult.skipped([this.reason]) : skipped = true;
}

/// The person's words, nothing else. A leftover English builder prefix
/// ("Skipped: ") is not a reason and is not required.
String? cleanSkipReason(String typed) {
  var t = typed.trim();
  if (t.toLowerCase().startsWith('skipped:')) {
    t = t.substring('skipped:'.length).trim();
  }
  return t.isEmpty ? null : t;
}

/// Close / tap-out / back. Words already on the sheet ARE the skip.
DidntHappenResult didntHappenOnDismiss(String typed) {
  final reason = cleanSkipReason(typed);
  if (reason == null) return const DidntHappenResult.closed();
  return DidntHappenResult.skipped(reason);
}

/// The labeled confirm door. Always a skip; reason rides along when present.
DidntHappenResult didntHappenOnConfirm(String typed) {
  return DidntHappenResult.skipped(cleanSkipReason(typed));
}
