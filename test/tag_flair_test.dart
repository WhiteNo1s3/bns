/// TAGS THE PERSON CHOSE, SHOWN BACK (owner, 2026-08-15: "we can add flare
/// for tags maybe"). The rules that keep flair from becoming clutter:
/// filing tags stay invisible, chosen ones speak in the person's language,
/// and a tag they invented themselves is still theirs to see.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/tag_flair.dart';

void main() {
  setUp(() => L.lang = 'en');

  test('the app\'s own filing tags never show', () {
    for (final plumbing in kPlumbingTags) {
      expect(tagLook(plumbing), isNull, reason: '$plumbing is plumbing');
    }
    // Case and padding are not a way past the rule.
    expect(tagLook('  Quick-Thought '), isNull);
    expect(tagLook(''), isNull);
  });

  test('a chosen tag speaks in words, not in its internal key', () {
    expect(tagLook('need-help')!.label, 'got in the way');
    expect(tagLook('felt out of bound')!.label, 'felt too much');
    L.lang = 'he';
    expect(tagLook('crisis')!.label, 'משבר');
    expect(tagLook('family')!.label, 'המשפחה יודעת');
  });

  test('a tag the person invented is kept, as they wrote it', () {
    final look = tagLook('my own thing');
    expect(look, isNotNull);
    expect(look!.label, 'my own thing');
  });
}
