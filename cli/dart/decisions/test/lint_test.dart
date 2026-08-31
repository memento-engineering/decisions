import 'package:decisions/decisions.dart';
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
}
