import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _sourceRegister =
    'test/fixtures/index_registers/source_repo/docs/decisions';
const _otherRegister =
    'test/fixtures/index_registers/other_repo/docs/decisions';
const _malformedRegister =
    'test/fixtures/index_registers/malformed_repo/docs/decisions';
const _malformedSlug =
    'intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel-'
    'and-an-overlong-fixture-marker';
const _malformedEntry = '$_malformedRegister/2026-01-03-$_malformedSlug.md';

Future<Map<String, dynamic>> _runJson(List<String> arguments) async {
  final output = StringBuffer();
  final runner = CommandRunner<int>('decisions', 'Decision register tools')
    ..addCommand(IndexCommand(output: output));
  expect(await runner.run(arguments), 0);
  return jsonDecode(output.toString()) as Map<String, dynamic>;
}

/// Runs `decisions` through the executable's own runner, which reports a
/// usage error on the error sink with exit 64 instead of rethrowing it.
Future<({int code, String out, String err})> _runCli(
  List<String> arguments,
) async {
  final output = StringBuffer();
  final error = StringBuffer();
  final code = await DecisionsCommandRunner(
    output: output,
    error: error,
  ).run(arguments);
  return (code: code, out: output.toString(), err: error.toString());
}

void main() {
  group('an unknown --surface register', () {
    test(
      'refuses a surface under a register the index does not carry',
      () async {
        final result = await _runCli([
          'index',
          '--surface',
          'nosuch_repo/README.md',
          _sourceRegister,
        ]);

        expect(result.code, 64);
        expect(result.out, isEmpty);
        expect(
          result.err,
          startsWith(
            'unknown register nosuch_repo in --surface nosuch_repo/README.md; '
            'indexed registers: source_repo\n\n',
          ),
        );
        expect(result.err, contains('Usage: decisions index'));
      },
    );

    test('refuses an unqualified surface', () async {
      final result = await _runCli([
        'index',
        '--surface',
        'README.md',
        _sourceRegister,
      ]);

      expect(result.code, 64);
      expect(result.out, isEmpty);
      expect(
        result.err,
        startsWith(
          'unknown register README.md in --surface README.md; '
          'indexed registers: source_repo\n',
        ),
      );
    });

    test('refuses an unknown register with --human', () async {
      final result = await _runCli([
        'index',
        '--human',
        '--surface',
        'nosuch_repo/README.md',
        _sourceRegister,
      ]);

      expect(result.code, 64);
      expect(result.out, isEmpty);
      expect(result.err, contains('unknown register nosuch_repo'));
    });

    test('lists every indexed register, sorted, when refusing', () async {
      final result = await _runCli([
        'index',
        '--surface',
        'nosuch_repo/README.md',
        _sourceRegister,
        _otherRegister,
      ]);

      expect(result.code, 64);
      expect(result.out, isEmpty);
      expect(
        result.err,
        contains('; indexed registers: other_repo, source_repo\n'),
      );
    });

    test('refuses a wildcard or absolute first segment', () async {
      for (final surface in ['*/README.md', '/source_repo/README.md']) {
        final result = await _runCli([
          'index',
          '--surface',
          surface,
          _sourceRegister,
        ]);

        expect(result.code, 64, reason: surface);
        expect(result.out, isEmpty, reason: surface);
        expect(
          result.err,
          contains('in --surface $surface; indexed registers: source_repo'),
          reason: surface,
        );
      }
    });

    test('accepts a ./ or backslash spelling of a known register', () async {
      for (final surface in [
        './source_repo/README.md',
        'source_repo\\README.md',
      ]) {
        final decoded = await _runJson([
          'index',
          '--surface',
          surface,
          _sourceRegister,
        ]);

        expect(decoded['decisions'], isEmpty, reason: surface);
        expect(decoded['diagnostics'], isEmpty, reason: surface);
      }
    });

    test('help says an unknown register is a usage error', () {
      final usage = IndexCommand(output: StringBuffer()).argParser.usage;

      expect(usage, contains('roster-qualified'));
      expect(usage, contains('usage error'));
      expect(usage, contains('exit 64'));
    });
  });

  test(
    'accepts explicit register paths and emits JSON without a station',
    () async {
      final output = StringBuffer();
      final runner = CommandRunner<int>('decisions', 'Decision register tools')
        ..addCommand(IndexCommand(output: output));

      final exitCode = await runner.run([
        'index',
        _sourceRegister,
        _otherRegister,
      ]);
      final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
      final decisions = (decoded['decisions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(exitCode, 0);
      expect(decoded['spec'], 2);
      expect(decisions, hasLength(2));
      expect(
        decisions.map((decision) => decision['originRegister']),
        containsAll(['source_repo', 'other_repo']),
      );
    },
  );

  test('requires at least one explicit register path', () async {
    final runner = CommandRunner<int>('decisions', 'Decision register tools')
      ..addCommand(IndexCommand(output: StringBuffer()));

    await expectLater(
      runner.run(['index']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
  });

  test('uses injected register paths lazily when no explicit paths', () async {
    var resolved = const <String>[];
    var calls = 0;
    final output = StringBuffer();
    final runner = CommandRunner<int>('decisions', 'Decision register tools')
      ..addCommand(
        IndexCommand(
          output: output,
          registerPaths: () {
            calls++;
            return resolved;
          },
        ),
      );

    expect(calls, 0);
    resolved = [_sourceRegister, _otherRegister];

    expect(await runner.run(['index']), 0);
    expect(calls, 1);
    final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
    expect(decoded['decisions'], hasLength(2));
  });

  test('emits schema-valid diagnostics in JSON and human output', () async {
    final decoded = await _runJson(['index', _malformedRegister]);
    final schemaDocument =
        jsonDecode(
              File(
                '../../../schema/decision-index.schema.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;
    final schema = JsonSchema.create(schemaDocument);

    expect(schema.validate(decoded).isValid, isTrue);
    expect(decoded['spec'], decisionIndexOutputSpec);
    expect(decoded['diagnostics'], [
      {
        'ruleId': DecisionLintRules.entrySchema,
        'file': _malformedEntry,
        'message': 'invalid `slug`',
      },
    ]);

    final output = StringBuffer();
    final runner = CommandRunner<int>('decisions', 'Decision register tools')
      ..addCommand(IndexCommand(output: output));
    expect(await runner.run(['index', '--human', _malformedRegister]), 0);
    expect(output.toString(), contains('decisions: 2'));
    expect(output.toString(), contains('diagnostics: 1'));
    expect(
      output.toString(),
      contains('$_malformedEntry: [entry.schema] invalid `slug`'),
    );
  });

  test('distinguishes clean no-match from an incomplete no-match', () async {
    final clean = await _runJson([
      'index',
      '--surface',
      'source_repo/README.md',
      _sourceRegister,
    ]);
    final incomplete = await _runJson([
      'index',
      '--surface',
      'malformed_repo/README.md',
      _malformedRegister,
    ]);

    expect(clean['decisions'], isEmpty);
    expect(clean['diagnostics'], isEmpty);
    expect(incomplete['decisions'], isEmpty);
    expect(incomplete['diagnostics'], hasLength(1));
  });

  test(
    'filters a grid worktree register by the store-qualified surface',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'decisions-index-command-',
      );
      try {
        final registerPath = p.join(
          sandbox.path,
          '.grid',
          'worktrees',
          'lenny',
          'lenny-0hgr',
          'docs',
          'decisions',
        );
        final register = await Directory(registerPath).create(recursive: true);
        await File(
          p.join(register.path, '2026-09-09-ci-policy.md'),
        ).writeAsString('''
---
status: accepted
date: 2026-09-09
decision-makers: [fixture]
register:
  spec: 1
  slug: ci-policy
  surfaces: [".github/workflows/ci.yaml"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# CI policy
''');

        final decoded = await _runJson([
          'index',
          registerPath,
          '--surface',
          'lenny/.github/workflows/ci.yaml',
        ]);
        final decisions = (decoded['decisions'] as List<dynamic>)
            .cast<Map<String, dynamic>>();

        expect(decisions, hasLength(1));
        expect(decisions.single['originRegister'], 'lenny');
        expect(decisions.single['slug'], 'ci-policy');
        expect(decisions.single['surfaces'], ['.github/workflows/ci.yaml']);
      } finally {
        await sandbox.delete(recursive: true);
      }
    },
  );
}
