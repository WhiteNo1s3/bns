/// How spoken words land in the person's text box.
///
/// THE BOX HOLDS ONLY THE PERSON'S WORDS (owner beta report, 2026-08-15:
/// a take with no transcript used to stamp "הקלטה 1" into the text — a
/// header the person never said, standing where their words should be:
/// "not close to my vision"). No labels, no stubs, no placeholders: words
/// append as plain new lines, and a wordless take writes NOTHING — the
/// voice itself is already kept and playable on its own chip.
library;

/// Label for take [n] (1-based) — used on the PLAYBACK CHIPS only,
/// never inside the person's text. Hebrew-first: "הקלטה 1".
String recordingLabel(int n, {required bool hebrew}) =>
    hebrew ? 'הקלטה $n' : 'Recording $n';

/// Append heard words as their own paragraph. Empty words append
/// nothing at all — the box is the person's, not the machine's.
String appendSpokenWords({
  required String current,
  required String words,
}) {
  final body = words.trim();
  if (body.isEmpty) return current;
  final cur = current.trimRight();
  if (cur.isEmpty) return '$body\n';
  return '$cur\n\n$body\n';
}
