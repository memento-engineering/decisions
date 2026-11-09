import 'dart:convert';
import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _repoRoot = '../../..';
const _selfHosted = '../../../docs/decisions';
const _fixtures = 'test/fixtures';

void main() {
  const service = DecisionLintService();

  test('self-hosted register is clean', () {
    final result = service.lint(registerPath: _selfHosted, repoRoot: _repoRoot);
    expect(result.isClean, isTrue, reason: '${result.toJson()}');
    expect(result.diagnostics, isEmpty);
  });

  test('fixture violations have distinct files and rule ids', () {
    final cases = <String, String>{
      'dangling_register': DecisionLintRules.edgeDanglingLocal,
      'duplicate_register': DecisionLintRules.identityDuplicateSlug,
      'graph_register': DecisionLintRules.forceObsoletedBy,
      'proposed_register': DecisionLintRules.statusProposed,
    };
    for (final MapEntry(key: directory, value: ruleId) in cases.entries) {
      final result = service.lint(
        registerPath: '$_fixtures/$directory',
        repoRoot: '.',
      );
      final diagnostic = result.diagnostics.firstWhere(
        (item) => item.ruleId == ruleId,
      );
      expect(diagnostic.file, endsWith('.md'));
      expect(diagnostic.message, isNotEmpty);
    }
  });

  test(
    'schema, cross-register, cache, surface, and spec rules are complete',
    () {
      final stale = service.lint(
        registerPath: '$_fixtures/graph_register',
        repoRoot: '.',
      );
      expect(
        stale.diagnostics.map((item) => item.ruleId),
        containsAll(<String>[
          DecisionLintRules.forceObsoletedBy,
          DecisionLintRules.forceUpdatedBy,
          DecisionLintRules.forceStatus,
        ]),
      );
      expect(
        stale.diagnostics.where(
          (item) => item.message.contains('other_repo#foreign-rule'),
        ),
        isEmpty,
      );

      final expected = <String, String>{
        'schema_register': DecisionLintRules.entrySchema,
        'surface_register': DecisionLintRules.surfaceUnmatched,
        'future_spec_register': DecisionLintRules.specUnsupported,
      };
      for (final MapEntry(key: directory, value: ruleId) in expected.entries) {
        final result = service.lint(
          registerPath: '$_fixtures/$directory',
          repoRoot: '.',
        );
        expect(result.diagnostics.map((item) => item.ruleId), contains(ruleId));
      }
    },
  );

  test('roster-wide exemption matches only marked unmatched surfaces', () {
    const marked = DecisionLintDiagnostic(
      ruleId: DecisionLintRules.surfaceUnmatched,
      file: 'docs/decisions/marked.md',
      message: 'surface "roster:CLAUDE.md" matched no filesystem entry',
    );
    const unmarked = DecisionLintDiagnostic(
      ruleId: DecisionLintRules.surfaceUnmatched,
      file: 'docs/decisions/unmarked.md',
      message: 'surface "CLAUDE.md" matched no filesystem entry',
    );
    const differentRule = DecisionLintDiagnostic(
      ruleId: DecisionLintRules.entrySchema,
      file: 'docs/decisions/schema.md',
      message: 'surface "roster:CLAUDE.md" matched no filesystem entry',
    );

    expect(isRosterWideSurfaceUnmatched(marked), isTrue);
    expect(isRosterWideSurfaceUnmatched(unmarked), isFalse);
    expect(isRosterWideSurfaceUnmatched(differentRule), isFalse);
  });

  test('deprecated updated target is lint-clean', () {
    final sandbox = Directory.systemTemp.createTempSync('decision-lint-force-');
    try {
      final register = Directory(p.join(sandbox.path, 'docs', 'decisions'))
        ..createSync(recursive: true);
      _writeUpdatedEntry(
        register,
        day: 1,
        slug: 'target',
        status: 'deprecated',
        updatedBy: const ['amendment'],
      );
      _writeUpdatedEntry(
        register,
        day: 2,
        slug: 'amendment',
        updates: const ['target'],
      );

      final result = service.lint(registerPath: register.path, repoRoot: '.');

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
      expect(result.diagnostics, isEmpty);
    } finally {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    }
  });

  test('updated target rejects every other non-accepted status', () {
    for (final status in <String>[
      'rejected',
      'proposed',
      'superseded by stale-rule',
    ]) {
      final sandbox = Directory.systemTemp.createTempSync(
        'decision-lint-force-',
      );
      try {
        final register = Directory(p.join(sandbox.path, 'docs', 'decisions'))
          ..createSync(recursive: true);
        _writeUpdatedEntry(
          register,
          day: 1,
          slug: 'target',
          status: status,
          updatedBy: const ['amendment'],
        );
        _writeUpdatedEntry(
          register,
          day: 2,
          slug: 'amendment',
          updates: const ['target'],
        );

        final result = service.lint(registerPath: register.path, repoRoot: '.');
        final targetRules = result.diagnostics
            .where(
              (diagnostic) => diagnostic.file.endsWith('2026-01-01-target.md'),
            )
            .map((diagnostic) => diagnostic.ruleId);

        expect(
          targetRules,
          contains(DecisionLintRules.forceStatus),
          reason: '$status: ${result.toJson()}',
        );
      } finally {
        if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
      }
    }
  });

  group('surface.unmatched applies only to an entry in force', () {
    late Directory sandbox;
    late Directory register;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('decision-lint-in-force-');
      register = Directory(p.join(sandbox.path, 'docs', 'decisions'))
        ..createSync(recursive: true);
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('an entry out of force may name surfaces that match nothing', () {
      _writeUpdatedEntry(
        register,
        day: 1,
        slug: 'old-rule',
        status: 'superseded by replacement',
        obsoletedBy: 'replacement',
        surfaces: const ['no-such-dir/**'],
      );
      _writeUpdatedEntry(
        register,
        day: 2,
        slug: 'replacement',
        obsoletes: const ['old-rule'],
      );
      _writeUpdatedEntry(
        register,
        day: 3,
        slug: 'vacated-rule',
        status: 'deprecated',
        surfaces: const ['no-such-dir/**'],
      );
      _writeUpdatedEntry(
        register,
        day: 4,
        slug: 'rejected-rule',
        status: 'rejected',
        surfaces: const ['no-such-dir/**'],
      );

      final result = service.lint(registerPath: register.path, repoRoot: '.');

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
      expect(result.diagnostics, isEmpty);
    });

    test('an entry in force must still resolve its surfaces', () {
      _writeUpdatedEntry(
        register,
        day: 1,
        slug: 'base-rule',
        updatedBy: const ['amendment'],
        surfaces: const ['no-such-dir/**'],
      );
      _writeUpdatedEntry(
        register,
        day: 2,
        slug: 'amendment',
        updates: const ['base-rule'],
      );
      _writeUpdatedEntry(
        register,
        day: 3,
        slug: 'plain-rule',
        surfaces: const ['no-such-dir/**'],
      );
      _writeUpdatedEntry(
        register,
        day: 4,
        slug: 'proposed-rule',
        status: 'proposed',
        surfaces: const ['no-such-dir/**'],
      );

      final result = service.lint(registerPath: register.path, repoRoot: '.');
      final unmatched = result.diagnostics
          .where((item) => item.ruleId == DecisionLintRules.surfaceUnmatched)
          .toList();

      expect(
        unmatched.map((item) => p.basename(item.file)),
        unorderedEquals(<String>[
          '2026-01-01-base-rule.md',
          '2026-01-03-plain-rule.md',
          '2026-01-04-proposed-rule.md',
        ]),
        reason: '${result.toJson()}',
      );
      for (final item in unmatched) {
        expect(
          item.message,
          'surface "no-such-dir/**" matched no filesystem entry',
        );
      }
      expect(
        result.diagnostics
            .where((item) => item.ruleId == DecisionLintRules.statusProposed)
            .map((item) => p.basename(item.file)),
        ['2026-01-04-proposed-rule.md'],
      );
    });
  });

  group('--max-slug-length', () {
    final longSlug = '${'a' * 59}-${'b' * 60}';
    late Directory sandbox;
    late String root;
    late String reg;
    late StringBuffer output;
    late StringBuffer error;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('decisions-max-slug-');
      root = p.join(sandbox.path, 'long_repo');
      reg = p.join(root, 'docs', 'decisions');
      File(p.join(root, 'README.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# fixture\n');
      _writeLongEntry(reg, longSlug);
      output = StringBuffer();
      error = StringBuffer();
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    Future<int> run(
      List<String> args, {
      DecisionSlugLimits slugLimits = const DecisionSlugLimits(),
    }) => DecisionsCommandRunner(
      output: output,
      error: error,
      registerPaths: () => [reg],
      slugLimits: slugLimits,
    ).run(args);

    test(
      'lint reads the long slug under the flag, and not without it',
      () async {
        expect(
          await run([
            'lint',
            reg,
            '--repo-root',
            root,
            '--max-slug-length',
            '160',
          ]),
          0,
        );
        expect(output.toString(), contains(': clean'));

        output.clear();
        expect(await run(['lint', reg, '--repo-root', root]), 1);
        expect(output.toString(), contains('[entry.schema] invalid `slug`'));
      },
    );

    test('index lists the long slug under the flag, and a diagnostic without '
        'it', () async {
      expect(await run(['index', '--max-slug-length', '160', reg]), 0);
      final limited = jsonDecode(output.toString()) as Map<String, Object?>;
      expect((limited['decisions']! as List).map((d) => (d as Map)['slug']), [
        longSlug,
      ]);
      expect(limited['diagnostics'], isEmpty);

      output.clear();
      expect(await run(['index', reg]), 0);
      final unlimited = jsonDecode(output.toString()) as Map<String, Object?>;
      expect(unlimited['decisions'], isEmpty);
      expect(unlimited['diagnostics'], hasLength(1));
      expect(
        ((unlimited['diagnostics']! as List).single as Map)['message'],
        'invalid `slug`',
      );
    });

    test('search finds the long slug under the flag, and reports it without '
        'it', () async {
      expect(await run(['search', '--max-slug-length', '160', 'aaaa']), 0);
      expect(output.toString(), contains('long_repo#$longSlug'));
      expect(output.toString(), contains('1 hit(s)'));
      expect(error.toString(), isEmpty);

      output.clear();
      expect(await run(['search', 'aaaa']), 0);
      expect(output.toString(), contains('0 hit(s)'));
      expect(error.toString(), contains('invalid `slug`'));
    });

    test('a composed limit reaches lint, and an explicit flag wins', () async {
      const composed = DecisionSlugLimits(byRegister: {'long_repo': 160});
      expect(
        await run(['lint', reg, '--repo-root', root], slugLimits: composed),
        0,
      );
      expect(output.toString(), contains(': clean'));

      output.clear();
      expect(
        await run([
          'lint',
          reg,
          '--repo-root',
          root,
          '--max-slug-length',
          '80',
        ], slugLimits: composed),
        1,
      );
      expect(output.toString(), contains('[entry.schema] invalid `slug`'));
    });

    for (final value in ['0', 'abc', '-3']) {
      test('--max-slug-length $value is a usage error', () async {
        expect(
          await run([
            'lint',
            reg,
            '--repo-root',
            root,
            '--max-slug-length',
            value,
          ]),
          DecisionsCommandRunner.usageExitCode,
        );
        expect(
          error.toString(),
          contains('--max-slug-length must be a positive integer'),
        );
        expect(output.toString(), isEmpty);
      });
    }
  });
}

/// Writes an accepted entry dated 2026-11-05 governing `README.md`.
void _writeLongEntry(String register, String slug) {
  File(p.join(register, '2026-11-05-$slug.md'))
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
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# A long rule

## Context and Problem Statement

Fixture.

## Decision Outcome

Fixture.
''');
}

File _writeUpdatedEntry(
  Directory register, {
  required int day,
  required String slug,
  String status = 'accepted',
  List<String> updates = const [],
  List<String> updatedBy = const [],
  List<String> surfaces = const ['test/**'],
  List<String> obsoletes = const [],
  String? obsoletedBy,
}) {
  final date = '2026-01-${day.toString().padLeft(2, '0')}';
  final file = File(p.join(register.path, '$date-$slug.md'));
  file.writeAsStringSync('''
---
status: $status
date: $date
decision-makers: [fixture]
register:
  spec: 1
  slug: $slug
  surfaces: [${surfaces.map((surface) => '"$surface"').join(', ')}]
  obsoletes: [${obsoletes.join(', ')}]
  updates: [${updates.join(', ')}]
  obsoleted-by: ${obsoletedBy ?? 'null'}
  updated-by: [${updatedBy.join(', ')}]
  bead: null
  legacy-id: null
---

# $slug
''');
  return file;
}
