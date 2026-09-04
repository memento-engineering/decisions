import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
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

void main() {
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
}
