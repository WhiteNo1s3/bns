/// How a finished take lands in the person's text box.
///
/// Each stop starts a new labeled block on a new line, so a second
/// recording does not smash into the first. The person can edit any
/// line before saving.
library;

/// Label for take [n] (1-based). Hebrew-first: "הקלטה 1".
String recordingLabel(int n, {required bool hebrew}) =>
    hebrew ? 'הקלטה $n' : 'Recording $n';

/// Append one finished take under [label]. Always ends with a newline
/// so the next take (or typed words) start on a fresh line.
String appendRecordingBlock({
  required String current,
  required String label,
  required String transcript,
}) {
  final body = transcript.trim();
  final block = body.isEmpty ? '$label\n' : '$label\n$body';
  final cur = current.trimRight();
  if (cur.isEmpty) return '$block\n';
  return '$cur\n\n$block\n';
}
