/// HEBREW FIRST MEANS THE CHROME FLIPS (owner, pushed 2026-08-22:
/// "Hebrew: physical left/right chrome becomes start/end"). A seam, a
/// gap, an alignment written in physical left/right sits on the wrong
/// side the moment the Row flips for RTL — the desktop rail's border
/// landed on the window edge. The fix was a sweep; this test is the law
/// that keeps the sweep from quietly undoing itself: every layout
/// construct in lib/ that names a physical side must be its directional
/// twin (start/end), unless the spot is deliberately physical and says
/// so in the allowlist below with its reason.
///
/// Symmetric `EdgeInsets.fromLTRB(a, _, a, _)` is direction-neutral and
/// allowed; an asymmetric one must be `EdgeInsetsDirectional.fromSTEB`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Deliberately physical spots: `path:line` → why.
const Map<String, String> _allow = {
  // (none yet — add 'lib/x.dart:123': 'reason' when a spot must stay physical,
  // e.g. a gradient direction or an LTR-only clock box)
};

final _patterns = <({RegExp re, String why})>[
  (
    re: RegExp(r'Alignment\.(centerLeft|centerRight|topLeft|topRight|bottomLeft|bottomRight)\b'),
    why: 'use AlignmentDirectional.*Start/*End'
  ),
  (
    re: RegExp(r'\bEdgeInsets\.only\([^)]*\b(left|right)\s*:'),
    why: 'use EdgeInsetsDirectional.only(start:/end:)'
  ),
  (
    re: RegExp(r'\bBorder\(\s*(left|right)\s*:'),
    why: 'use BorderDirectional(start:/end:)'
  ),
  (
    re: RegExp(r'\bPositioned\(\s*(left|right)\s*:'),
    why: 'use PositionedDirectional(start:/end:)'
  ),
  (
    re: RegExp(r'TextAlign\.(left|right)\b'),
    why: 'use TextAlign.start/end'
  ),
  (
    re: RegExp(r'BorderRadius\.only\([^)]*(Left|Right)\s*:'),
    why: 'use BorderRadiusDirectional.only(topStart/...)'
  ),
  (
    re: RegExp(r'BorderRadius\.horizontal\([^)]*\b(left|right)\s*:'),
    why: 'use BorderRadiusDirectional.horizontal(start:/end:)'
  ),
];

final _ltrb = RegExp(r'EdgeInsets\.fromLTRB\(\s*([^,()]+?)\s*,\s*[^,()]+?\s*,\s*([^,()]+?)\s*,');

void main() {
  test('no physical left/right chrome in lib/ — directional or allowlisted', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in files) {
      final lines = f.readAsLinesSync();
      // fromLTRB may span lines — join, keep a line index for reporting.
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        final key = '${f.path}:${i + 1}';
        if (_allow.containsKey(key)) continue;
        for (final p in _patterns) {
          if (p.re.hasMatch(line)) {
            offenders.add('$key  ${p.why}\n      ${line.trim()}');
          }
        }
        if (line.contains('EdgeInsets.fromLTRB(')) {
          // Gather up to six lines so a call with one argument per line is
          // judged whole (caregiver_home writes them that way).
          final joined = [
            for (var k = i; k < lines.length && k < i + 6; k++) lines[k]
          ].join(' ');
          final m = _ltrb.firstMatch(joined);
          if (m != null && m.group(1)!.trim() != m.group(2)!.trim()) {
            offenders.add(
                '$key  asymmetric fromLTRB — use EdgeInsetsDirectional.fromSTEB\n      ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Physical left/right chrome sits on the wrong side in Hebrew. '
            'Make it directional, or allowlist the spot with its reason:\n'
            '${offenders.join('\n')}');
  });
}
