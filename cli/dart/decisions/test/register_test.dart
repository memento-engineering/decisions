import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
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
      final beads = {for (final entry in entries) entry.slug: entry.bead};
      expect(beads['docket-triggers'], 'dec-iut');
      expect(beads['lexical-precedent-search'], 'dec-5q9');
      expect(
        beads['force-mutations-scope-cleanliness-to-touched-entries'],
        'dec-3g7',
      );
      expect(
        beads['successor-updated-by-dirt-does-not-block-force-mutation'],
        'dec-o67',
      );
      expect(beads['cross-register-force-edges'], 'dec-b17');
      expect(
        beads['the-decisions-cli-ships-as-prebuilt-binaries'],
        'dec-n8y.2',
      );
      expect(
        beads['a-registers-style-md-is-its-style-guide-and-uppercase-files-'
            'are-not-entries'],
        'dec-vqt',
      );
      expect(beads['decisions-new-owns-the-write-mechanics'], 'dec-dmq');
      expect(
        beads['the-decisions-binary-carries-its-own-agent-instructions'],
        'dec-mtj',
      );
      expect(
        beads['a-skill-stub-names-its-fallback-when-the-decisions-binary-is-'
            'missing'],
        'dec-2ow',
      );
      expect(
        beads['decisions-doctor-answers-whether-this-binary-can-work-this-'
            'register'],
        'dec-2nx',
      );
      expect(
        beads['templates-style-md-is-the-starter-style-guide-for-a-register'],
        'dec-1ee',
      );
      expect(
        beads['the-register-ships-to-gas-city-as-a-pack-of-guide-stubs'],
        'dec-iiq',
      );
      expect(
        beads['each-release-prints-and-smoke-tests-its-gas-city-pin'],
        'dec-p7f.7.5',
      );
      expect(
        beads['the-gas-city-pack-ships-no-orders-and-register-health-belongs-'
            'in-each-rigs-ci'],
        'dec-kch',
      );
      expect(
        beads['spec-tier-table-describes-capabilities-and-defers-the-verb-'
            'list-to-the-cli'],
        'dec-9ed',
      );
      expect(
        beads['every-verb-prints-refusals-and-errors-on-stderr-and-results-'
            'on-stdout'],
        'dec-p6z',
      );
      beads.remove('docket-triggers');
      beads.remove('lexical-precedent-search');
      beads.remove('force-mutations-scope-cleanliness-to-touched-entries');
      beads.remove('successor-updated-by-dirt-does-not-block-force-mutation');
      beads.remove('cross-register-force-edges');
      beads.remove('the-decisions-cli-ships-as-prebuilt-binaries');
      beads.remove(
        'a-registers-style-md-is-its-style-guide-and-uppercase-files-'
        'are-not-entries',
      );
      beads.remove('decisions-new-owns-the-write-mechanics');
      beads.remove('the-decisions-binary-carries-its-own-agent-instructions');
      beads.remove(
        'a-skill-stub-names-its-fallback-when-the-decisions-binary-is-missing',
      );
      beads.remove(
        'decisions-doctor-answers-whether-this-binary-can-work-this-register',
      );
      beads.remove(
        'templates-style-md-is-the-starter-style-guide-for-a-register',
      );
      beads.remove('the-register-ships-to-gas-city-as-a-pack-of-guide-stubs');
      beads.remove('each-release-prints-and-smoke-tests-its-gas-city-pin');
      beads.remove(
        'the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-'
        'each-rigs-ci',
      );
      beads.remove(
        'spec-tier-table-describes-capabilities-and-defers-the-verb-list-to-'
        'the-cli',
      );
      beads.remove(
        'every-verb-prints-refusals-and-errors-on-stderr-and-results-on-stdout',
      );
      beads.remove(
        'decisions-migrate-legacy-is-retired-with-the-legacy-registers-it-'
        'converted',
      );
      expect(beads.values, everyElement(isNull));
      expect(entries.map((entry) => entry.legacyId), everyElement(isNull));
    });

    test('parses cached force fields', () {
      final root = entries.singleWhere(
        (entry) => entry.slug == 'the-decision-register',
      );
      expect(root.cachedObsoletedBy, isNull);
      expect(
        root.cachedUpdatedBy,
        unorderedEquals([
          'madr-profile',
          'entry-identity',
          'spec-and-artifact-versioning',
          'docket-triggers',
          'lexical-precedent-search',
          'force-mutations-scope-cleanliness-to-touched-entries',
          'decisions-new-owns-the-write-mechanics',
        ]),
      );
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

  group("a register's slug limit", () {
    final longSlug = '${'a' * 59}-${'b' * 60}';
    late Directory sandbox;
    late String longRoot;
    late String longRegister;
    late String otherRegister;
    late String longFile;

    setUp(() {
      expect(longSlug, hasLength(120));
      sandbox = Directory.systemTemp.createTempSync('decisions-slug-limit-');
      longRoot = p.join(sandbox.path, 'long_repo');
      longRegister = p.join(longRoot, 'docs', 'decisions');
      otherRegister = p.join(sandbox.path, 'other_repo', 'docs', 'decisions');
      for (final root in [longRoot, p.join(sandbox.path, 'other_repo')]) {
        File(p.join(root, 'README.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('# fixture\n');
      }
      longFile = _writeLimitEntry(longRegister, longSlug);
      _writeLimitEntry(otherRegister, longSlug);
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    Matcher invalidSlug() => throwsA(
      isA<DecisionParseException>().having(
        (error) => error.message,
        'message',
        'invalid `slug`',
      ),
    );

    test('parseEntry applies the limit it is given', () {
      expect(() => parseEntry(longFile), invalidSlug());
      expect(() => parseEntry(longFile, maxSlugLength: 119), invalidSlug());
      expect(parseEntry(longFile, maxSlugLength: 120).slug, longSlug);
      expect(parseEntry(longFile, maxSlugLength: 160).slug, longSlug);
    });

    test('readRegister applies the limit to every entry', () {
      expect(
        readRegister(longRegister, maxSlugLength: 160).map((e) => e.slug),
        [longSlug],
      );
    });

    test('DecisionSlugLimits resolves a register, by name or by path', () {
      expect(defaultMaxSlugLength, 80);
      expect(const DecisionSlugLimits().fallback, defaultMaxSlugLength);
      expect(const DecisionSlugLimits().forRegister('long_repo'), 80);
      expect(const DecisionSlugLimits().forRegister(null), 80);
      expect(const DecisionSlugLimits.uniform(40).forRegister('any'), 40);
      const limits = DecisionSlugLimits(
        fallback: 90,
        byRegister: {'long_repo': 160},
      );
      expect(limits.forRegister('long_repo'), 160);
      expect(limits.forRegister('other_repo'), 90);
      expect(limits.forRegisterPath(longRegister), 160);
      expect(limits.forRegisterPath(otherRegister), 90);
    });

    test('a union applies each register its own limit', () {
      final union = DecisionRegisterUnion.fromRegisterPaths([
        longRegister,
        otherRegister,
      ], slugLimits: const DecisionSlugLimits(byRegister: {'long_repo': 160}));

      expect(
        union.findRegister('long_repo')!.graph.entries.keys,
        contains(longSlug),
      );
      expect(union.findRegister('other_repo')!.graph.entries, isEmpty);
      expect(union.diagnostics, hasLength(1));
      expect(union.diagnostics.single.message, 'invalid `slug`');
      expect(union.diagnostics.single.file, contains('other_repo'));
    });

    test('a roster reads a sibling under the limit its caller supplies', () {
      final reference = DecisionReference(
        register: 'long_repo',
        reference: longSlug,
      );
      final limited = DecisionRegisterRoster.fromRegisterPaths([
        longRegister,
      ], slugLimits: const DecisionSlugLimits(byRegister: {'long_repo': 160}));
      expect(limited.resolveReference(reference)?.slug, longSlug);

      final unlimited = DecisionRegisterRoster.fromRegisterPaths([
        longRegister,
      ]);
      expect(unlimited.resolveReference(reference), isNull);
    });

    test('index and search list the entry under the limit', () {
      const limits = DecisionSlugLimits(byRegister: {'long_repo': 160});
      final index = DecisionIndex.fromRegisterPaths([
        longRegister,
      ], slugLimits: limits);
      expect(index.decisions.map((d) => d.slug), [longSlug]);
      expect(index.diagnostics, isEmpty);

      final result = const DecisionSearchService().search(
        query: 'aaaa',
        registerPaths: [longRegister],
        slugLimits: limits,
      );
      expect(result.hits.map((hit) => hit.slug), [longSlug]);
      expect(result.diagnostics, isEmpty);
    });

    test('lint parses under the limit', () {
      final clean = const DecisionLintService(
        slugLimits: DecisionSlugLimits.uniform(160),
      ).lint(registerPath: longRegister, repoRoot: longRoot);
      expect(clean.diagnostics, isEmpty);

      final dirty = const DecisionLintService().lint(
        registerPath: longRegister,
        repoRoot: longRoot,
      );
      expect(dirty.diagnostics.map((d) => '${d.ruleId} ${d.message}'), [
        'entry.schema invalid `slug`',
      ]);
    });

    test('a force mutation reads and lints its candidate under the limit', () {
      _writeLimitEntry(longRegister, 'amends-long-rule', updates: [longSlug]);
      final before = File(longFile).readAsStringSync();

      expect(
        () => const DecisionMutationService().update(
          registerPath: longRegister,
          repoRoot: longRoot,
          target: longSlug,
          successor: 'amends-long-rule',
        ),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            contains('invalid `slug`'),
          ),
        ),
      );
      expect(File(longFile).readAsStringSync(), before);

      const limits = DecisionSlugLimits.uniform(160);
      const DecisionMutationService(slugLimits: limits).update(
        registerPath: longRegister,
        repoRoot: longRoot,
        target: longSlug,
        successor: 'amends-long-rule',
      );
      expect(parseEntry(longFile, maxSlugLength: 160).cachedUpdatedBy, [
        'amends-long-rule',
      ]);
      expect(
        const DecisionLintService(
          slugLimits: limits,
        ).lint(registerPath: longRegister, repoRoot: longRoot).diagnostics,
        isEmpty,
      );
    });

    test('a write lints its candidate under the limit', () {
      final secondSlug = '${'c' * 59}-${'d' * 60}';
      final result =
          DecisionRecordService(
            clock: () => DateTime(2026, 11, 5),
            slugLimits: const DecisionSlugLimits.uniform(160),
          ).record(
            registerPath: longRegister,
            repoRoot: longRoot,
            draft: DecisionDraft(
              slug: secondSlug,
              title: 'A second long rule',
              surfaces: const ['README.md'],
              decisionMakers: const ['nico'],
              body: _limitBody,
            ),
          );
      expect(result.path, p.join(longRegister, '2026-11-05-$secondSlug.md'));
      expect(parseEntry(result.path, maxSlugLength: 160).slug, secondSlug);
    });

    test('lib holds one literal 80, the default', () {
      final standalone = RegExp(r'(?<![0-9A-Za-z_])80(?![0-9A-Za-z_])');
      final hits = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (standalone.hasMatch(lines[i])) {
            hits.add('${p.normalize(file.path)}:${lines[i].trim()}');
          }
        }
      }
      expect(hits, [
        '${p.join('lib', 'src', 'entry.dart')}:'
            'const defaultMaxSlugLength = 80;',
      ]);
    });
  });
}

const _limitBody = '''
## Context and Problem Statement

Fixture.

## Decision Outcome

Fixture.
''';

/// Writes an accepted entry dated 2026-11-05 governing `README.md`, and
/// returns its path.
String _writeLimitEntry(
  String register,
  String slug, {
  List<String> updates = const [],
}) {
  final file = File(p.join(register, '2026-11-05-$slug.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
---
status: accepted
date: 2026-11-05
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: "$slug"
  surfaces:
    - "README.md"
  obsoletes: []
  updates: [${updates.map((u) => '"$u"').join(', ')}]
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $slug

$_limitBody''');
  return file.path;
}
