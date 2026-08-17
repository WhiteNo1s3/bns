/// MARKS THAT OFFER THEMSELVES — fluency without a single new screen.
///
/// Owner, 2026-08-17: tagging "gotta be fluent... find new idea on how to
/// create the tags efficiently." The idea: the marks are already IN the
/// person's words — surface them. These tests hold the offering to its
/// manners: person's own words lead, English matches whole words only,
/// reserved doors never volunteer, nothing exceeds a calm handful.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:bns/core/models/models.dart';
import 'package:bns/core/tag_flair.dart';

void main() {
  group('suggestMarksFor', () {
    test('a Hebrew word surfaces its mark', () {
      expect(suggestMarksFor('היה משבר גדול היום'), contains('crisis'));
    });

    test('an English label matches whole words only', () {
      expect(suggestMarksFor('a good day'), contains('good'));
      expect(suggestMarksFor('goodbye world'), isNot(contains('good')),
          reason: '"good" must not hide inside "goodbye"');
    });

    test('the person\'s own past word leads the offers', () {
      final offers = suggestMarksFor(
        'עבדתי בגינה והיה משבר קטן',
        vocabulary: const ['גינה'],
      );
      expect(offers.first, 'גינה',
          reason: 'their own words are their language — they lead');
      expect(offers, contains('crisis'));
    });

    test('Hebrew prefixes come free by containment', () {
      expect(suggestMarksFor('הכול קרה בגינה', vocabulary: const ['גינה']),
          contains('גינה'));
    });

    test('already-chosen marks are not re-offered', () {
      expect(
          suggestMarksFor('משבר', alreadyChosen: const ['crisis']), isEmpty);
    });

    test('reserved doors never volunteer', () {
      // «סערה» is the storm's label; the storm has its own door.
      expect(suggestMarksFor('הייתה סערה גדולה'), isNot(contains('mad-vent')));
      expect(
          suggestMarksFor('storm and drama',
              vocabulary: const ['mad-vent', 'family']),
          isNot(anyOf(contains('mad-vent'), contains('family'))));
    });

    test('a calm handful, never a flood', () {
      final offers = suggestMarksFor(
        'good drama crisis wondering הרגשתי בטוח',
        max: 3,
      );
      expect(offers.length, lessThanOrEqualTo(3));
    });

    test('empty words offer nothing', () {
      expect(suggestMarksFor('   '), isEmpty);
    });
  });

  group('ownMarksOf — the person\'s vocabulary', () {
    QuickCapture kept(String id, List<String> tags) => QuickCapture(
          id: id,
          at: DateTime(2026, 8, 16),
          text: 'משהו',
          tags: tags,
          memoryLevel: MemoryLevel.remember,
        );

    test('own words only — built-ins and reserved doors are not vocabulary',
        () {
      final vocab = ownMarksOf([
        kept('a', ['גינה', 'crisis']),
        kept('b', ['family', 'need-help', 'שירה']),
        kept('c', ['quick-thought', 'גינה']),
      ]);
      expect(vocab, ['גינה', 'שירה']);
    });

    test('freshest first, deduped across spellings', () {
      final vocab = ownMarksOf([
        kept('new', ['#שירה']),
        kept('old', ['שירה', 'גינה']),
      ]);
      expect(vocab.length, 2);
      expect(canonicalTag(vocab.first), 'שירה');
    });
  });
}
