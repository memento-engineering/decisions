import 'package:decisions/decisions.dart';
import 'package:test/test.dart';

/// This repository's own register, relative to the package root.
const _register = '../../../docs/decisions';

void main() {
  group('readRegister over the self-hosted register', () {
    late List<DecisionEntry> entries;

    setUpAll(() => entries = readRegister(_register));

    test('parses every entry', () {
      expect(entries, isNotEmpty);
    });

    test('every entry declares spec 1', () {
      expect(entries.map((e) => e.spec), everyElement(1));
    });

    test('slugs are unique', () {
      final slugs = entries.map((e) => e.slug).toList();
      expect(slugs.toSet(), hasLength(slugs.length));
    });

    test('this profile never uses proposed', () {
      expect(entries.map((e) => e.status), isNot(contains('proposed')));
    });

    test('optional authored identities default to null', () {
      expect(entries.map((entry) => entry.bead), everyElement(isNull));
      expect(entries.map((entry) => entry.legacyId), everyElement(isNull));
    });

    test('every authored edge resolves within the register', () {
      final known = {for (final e in entries) e.slug};
      for (final entry in entries) {
        for (final ref in [...entry.obsoletes, ...entry.updates]) {
          if (ref.contains('#')) continue; // cross-register; not resolved here
          expect(
            known,
            contains(ref),
            reason: '${entry.slug} points at unknown entry "$ref"',
          );
        }
      }
    });

    test('the constitutive entry is present and binding', () {
      final root = entries.singleWhere(
        (e) => e.slug == 'the-decision-register',
      );
      expect(root.isBinding, isTrue);
      expect(root.decisionMakers, contains('nico'));
    });

    test('retains the authored Markdown body without front matter', () {
      final root = entries.singleWhere(
        (entry) => entry.slug == 'the-decision-register',
      );

      expect(
        root.body,
        startsWith(
          '# A decision register is a citation graph with force, '
          'recorded by anyone and ratified at a docket',
        ),
      );
      expect(root.body, contains('## Decision Outcome'));
      expect(root.body, isNot(startsWith('---')));
    });
  });

  test('a file without front matter is rejected', () {
    expect(
      () => parseEntry('../../../README.md'),
      throwsA(isA<DecisionParseException>()),
    );
  });
}
