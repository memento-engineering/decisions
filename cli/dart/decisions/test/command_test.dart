import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
import 'package:test/test.dart';

final class FakeDecisionLinter implements DecisionLinter {
  FakeDecisionLinter(this.result);

  final DecisionLintResult result;
  String? registerPath;
  String? repoRoot;

  @override
  DecisionLintResult lint({
    required String registerPath,
    required String repoRoot,
  }) {
    this.registerPath = registerPath;
    this.repoRoot = repoRoot;
    return result;
  }
}

final class FakeLegacyRegisterConverter implements LegacyRegisterConverter {
  String? registerFile;
  List<LegacyRatifiedAdr>? ratifiedAdrs;
  List<String>? surfaces;
  String? human;
  String? outputDirectory;

  @override
  LegacyConversionResult convert({
    required String registerFile,
    required Iterable<LegacyRatifiedAdr> ratifiedAdrs,
    required Iterable<String> surfaces,
    required String human,
    required String outputDirectory,
  }) {
    this.registerFile = registerFile;
    this.ratifiedAdrs = ratifiedAdrs.toList(growable: false);
    this.surfaces = surfaces.toList(growable: false);
    this.human = human;
    this.outputDirectory = outputDirectory;
    return LegacyConversionResult(['docs/decisions/converted.md']);
  }
}

void main() {
  test('json output validates against its schema', () async {
    final output = StringBuffer();
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        DecisionsCommand(linter: const DecisionLintService(), output: output),
      );

    final code = await runner.run(<String>[
      'decisions',
      'lint',
      'test/fixtures/dangling_register',
      '--repo-root',
      '.',
      '--json',
    ]);
    final Object? decoded = jsonDecode(output.toString());
    final Object? schemaDocument = jsonDecode(
      File('../../../schema/lint-result.schema.json').readAsStringSync(),
    );
    final schema = JsonSchema.create(schemaDocument as Map<String, Object?>);

    expect(code, 1);
    expect(schema.validate(decoded).isValid, isTrue);
    expect(
      (decoded as Map<String, Object?>).keys,
      unorderedEquals(<String>[
        'schemaVersion',
        'register',
        'valid',
        'diagnostics',
      ]),
    );
  });

  test('decisions command composes and returns gating exit codes', () async {
    final cleanRunner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        DecisionsCommand(
          linter: const DecisionLintService(),
          output: StringBuffer(),
        ),
      );
    expect(
      await cleanRunner.run(<String>[
        'decisions',
        'lint',
        '../../../docs/decisions',
        '--repo-root',
        '../../..',
        '--json',
      ]),
      0,
    );

    final clean = DecisionLintResult(
      register: 'docs/decisions',
      diagnostics: const <DecisionLintDiagnostic>[],
    );
    final fake = FakeDecisionLinter(clean);
    final output = StringBuffer();
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(DecisionsCommand(linter: fake, output: output));

    final cleanCode = await runner.run(<String>[
      'decisions',
      'lint',
      'register-path',
      '--repo-root',
      'repo-path',
      '--json',
    ]);
    expect(cleanCode, 0);
    expect(fake.registerPath, 'register-path');
    expect(fake.repoRoot, 'repo-path');
    expect(output.toString(), startsWith('{'));

    final invalidOutput = StringBuffer();
    final invalidRunner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        DecisionsCommand(
          linter: FakeDecisionLinter(
            DecisionLintResult(
              register: 'register-path',
              diagnostics: const <DecisionLintDiagnostic>[
                DecisionLintDiagnostic(
                  ruleId: DecisionLintRules.statusProposed,
                  file: 'entry.md',
                  message: 'this profile never uses proposed',
                ),
              ],
            ),
          ),
          output: invalidOutput,
        ),
      );
    expect(
      await invalidRunner.run(<String>['decisions', 'lint', 'register-path']),
      1,
    );
  });

  test('migrate-legacy command delegates explicit inputs', () async {
    final converter = FakeLegacyRegisterConverter();
    final output = StringBuffer();
    final runner = CommandRunner<int>(
      'station',
      'fixture',
    )..addCommand(DecisionsCommand(legacyConverter: converter, output: output));

    final code = await runner.run(<String>[
      'decisions',
      'migrate-legacy',
      'docs/adr/ADR-0000-ai-decision-register.md',
      'docs/decisions',
      '--surface',
      'lib/**',
      '--surface',
      'docs/**',
      '--human',
      'Nico Spencer',
      '--ratified',
      '2026-06-11=docs/adr/ADR-0001-foundations.md',
    ]);

    expect(code, 0);
    expect(converter.registerFile, 'docs/adr/ADR-0000-ai-decision-register.md');
    expect(converter.outputDirectory, 'docs/decisions');
    expect(converter.surfaces, ['lib/**', 'docs/**']);
    expect(converter.human, 'Nico Spencer');
    expect(converter.ratifiedAdrs, hasLength(1));
    expect(converter.ratifiedAdrs!.single.date, '2026-06-11');
    expect(
      converter.ratifiedAdrs!.single.file,
      'docs/adr/ADR-0001-foundations.md',
    );
    expect(output.toString(), 'converted 1 decision entries\n');
  });
}
