/// TAGS THE PERSON CHOSE, SHOWN BACK (owner, 2026-08-15: "we can add flare
/// for tags maybe"). The rules that keep flair from becoming clutter:
/// filing tags stay invisible, chosen ones speak in the person's language,
/// and a tag they invented themselves is still theirs to see.
///
/// Extended 2026-08-16 (owner: "improve to maximum the tagging system"):
/// marks are choosable, findable in the person's language, and filterable.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bns/core/i18n/l.dart';
import 'package:bns/core/models/models.dart';
import 'package:bns/core/tag_flair.dart';

QuickCapture _kept(String id, {String? text, List<String> tags = const []}) =>
    QuickCapture(
      id: id,
      at: DateTime(2026, 8, 16, 12),
      text: text,
      tags: tags,
    );

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

  test('an ask wears words, never its internal key', () {
    expect(tagLook('asked-help')!.label, 'asked for help');
    L.lang = 'he';
    expect(tagLook('asked-help')!.label, 'ביקשתי עזרה');
  });

  test('one spelling for comparing: no #, no case, no stray spaces', () {
    expect(canonicalTag(' #Crisis '), 'crisis');
    expect(canonicalTag('משבר'), 'משבר');
  });

  test('search speaks the person\'s language — «משבר» finds crisis', () {
    expect(tagMatchesQuery('crisis', 'משבר'), isTrue);
    expect(tagMatchesQuery('crisis', 'cri'), isTrue);
    expect(tagMatchesQuery('mad-vent', 'storm'), isTrue);
    expect(tagMatchesQuery('mad-vent', 'סערה'), isTrue);
    expect(tagMatchesQuery('felt out of bound', 'יותר מדי'), isTrue);
    expect(tagMatchesQuery('crisis', 'שגרה'), isFalse);
    // A person's own word answers to itself, however it was decorated.
    expect(tagMatchesQuery('#ים', 'ים'), isTrue);
  });

  test('a memory answers by its words or by any of its marks', () {
    final byWords = _kept('a', text: 'הלכתי לים');
    final byMark = _kept('b', text: 'בלי מילים', tags: ['crisis']);
    expect(memoryMatchesQuery(byWords, 'לים'), isTrue);
    expect(memoryMatchesQuery(byMark, 'משבר'), isTrue);
    expect(memoryMatchesQuery(byMark, 'crisis'), isTrue);
    expect(memoryMatchesQuery(byMark, 'שום דבר'), isFalse);
    expect(memoryMatchesQuery(byMark, ''), isTrue);
  });

  test('filter row offers each visible mark once, plumbing never', () {
    final items = [
      _kept('a', tags: ['quick-thought', 'good']),
      _kept('b', tags: ['#Good', 'crisis']),
      _kept('c', tags: ['day-idea', 'ים שלי']),
    ];
    expect(flairTagsOf(items), ['good', 'crisis', 'ים שלי']);
  });

  test('a mark is found under any spelling it was stored with', () {
    final m = _kept('a', tags: ['#Crisis ']);
    expect(memoryHasTag(m, 'crisis'), isTrue);
    expect(memoryHasTag(m, 'good'), isFalse);
    expect(tagsHaveFlair(m.tags), isTrue);
    expect(tagsHaveFlair(const ['quick-thought']), isFalse);
  });

  test('the choosable marks all have looks and stay out of reserved doors',
      () {
    for (final key in kChoosableMarks) {
      expect(tagLook(key), isNotNull, reason: '$key must have a look');
      expect(kPickerReservedTags.contains(key), isFalse,
          reason: '$key must not be reserved');
      expect(kPlumbingTags.contains(key), isFalse,
          reason: '$key must not be plumbing');
    }
    // The gentlest word leads; the hard word is offered last, never first.
    expect(kChoosableMarks.first, 'good');
    expect(kChoosableMarks.last, 'crisis');
  });
}
