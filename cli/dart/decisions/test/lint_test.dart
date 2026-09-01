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

  test('deprecated updated target is lint-clean', () {
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
        status: 'deprecated',
        updatedBy: const ['amendment'],
      );
      _writeUpdatedEntry(
        register,
        day: 2,
        slug: 'amendment',
        updates: const ['target'],
      );

      final result = service.lint(
        registerPath: register.path,
        repoRoot: '.',
      );

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

        final result = service.lint(
          registerPath: register.path,
          repoRoot: '.',
        );
        final targetRules = result.diagnostics
            .where(
              (diagnostic) =>
                  diagnostic.file.endsWith('2026-01-01-target.md'),
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
}

File _writeUpdatedEntry(
  Directory register, {
  required int day,
  required String slug,
  String status = 'accepted',
  List<String> updates = const [],
  List<String> updatedBy = const [],
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
  surfaces: ["test/**"]
  obsoletes: []
  updates: [${updates.join(', ')}]
  obsoleted-by: null
  updated-by: [${updatedBy.join(', ')}]
  bead: null
  legacy-id: null
---

# $slug
''');
  return file;
}
