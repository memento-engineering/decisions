import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A linter that returns one fixed result, so a test can hold any diagnostic.
final class _FixedLinter implements DecisionLinter {
  _FixedLinter(this.result);

  final DecisionLintResult result;

  @override
  DecisionLintResult lint({
    required String registerPath,
    required String repoRoot,
  }) => result;
}

/// One run of a host: its exit code and both streams.
typedef _Run = ({int code, String out, String err});

/// Runs the standalone `decisions` runner over [args].
Future<_Run> _standalone(List<String> args, {DecisionLinter? linter}) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await DecisionsCommandRunner(
    linter: linter,
    output: out,
    error: err,
  ).run(args);
  return (code: code, out: out.toString(), err: err.toString());
}

/// Runs a composed host, `station decisions ...`, over [args].
Future<_Run> _grouped(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final runner = CommandRunner<int>('station', 'fixture')
    ..addCommand(DecisionsCommand(output: out, error: err));
  final code = await runner.run(['decisions', ...args]) ?? 0;
  return (code: code, out: out.toString(), err: err.toString());
}

/// Writes one spec-1 entry into [register].
void _writeEntry(
  Directory register,
  String file, {
  required String slug,
  List<String> surfaces = const ['docs/decisions/**'],
  List<String> updates = const [],
}) {
  File(p.join(register.path, file)).writeAsStringSync('''
---
status: accepted
date: ${file.substring(0, 10)}
decision-makers: [fixture]
register:
  spec: 1
  slug: $slug
  surfaces: ${jsonEncode(surfaces)}
  obsoletes: []
  updates: ${jsonEncode(updates)}
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---
# $slug
''');
}

/// The parity reference: memento-engineering's `tool/lint_register.dart`
/// exit code, reproduced over a lint result. A missing register exits 2
/// there before it lints; otherwise any non-exempt diagnostic exits 1.
int _referenceExit(DecisionLintResult? result) {
  if (result == null) return 2;
  final fatal = result.diagnostics.where(
    (diagnostic) => !isRosterWideSurfaceUnmatched(diagnostic),
  );
  return fatal.isEmpty ? 0 : 1;
}

const _rosterMessage = 'surface "roster:CLAUDE.md" matched no filesystem entry';
const _localMessage = 'surface "CLAUDE.md" matched no filesystem entry';

const _rosterSurface = DecisionLintDiagnostic(
  ruleId: DecisionLintRules.surfaceUnmatched,
  file: 'docs/decisions/2026-01-01-roster-rule.md',
  message: _rosterMessage,
);
const _localSurface = DecisionLintDiagnostic(
  ruleId: DecisionLintRules.surfaceUnmatched,
  file: 'docs/decisions/2026-01-02-local-rule.md',
  message: _localMessage,
);

/// Every rule id [DecisionLintRules] declares.
const _ruleIds = <String>[
  DecisionLintRules.entrySchema,
  DecisionLintRules.identityFilename,
  DecisionLintRules.identityDuplicateSlug,
  DecisionLintRules.identityDuplicateReference,
  DecisionLintRules.statusProposed,
  DecisionLintRules.edgeInvalidReference,
  DecisionLintRules.edgeDanglingLocal,
  DecisionLintRules.edgeAmbiguousLocal,
  DecisionLintRules.edgeDanglingCrossRegister,
  DecisionLintRules.forceObsoletedBy,
  DecisionLintRules.forceUpdatedBy,
  DecisionLintRules.forceStatus,
  DecisionLintRules.surfaceUnmatched,
  DecisionLintRules.specUnsupported,
];

void main() {
  late Directory temp;
  late Directory register;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('lint_gate_');
    register = Directory(p.join(temp.path, 'docs', 'decisions'))
      ..createSync(recursive: true);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  List<String> gateArgs({bool gate = true, bool json = false}) => [
    'lint',
    if (gate) '--gate',
    if (json) '--json',
    register.path,
    '--repo-root',
    temp.path,
  ];

  void writeRosterRule() => _writeEntry(
    register,
    '2026-01-01-roster-rule.md',
    slug: 'roster-rule',
    surfaces: ['roster:CLAUDE.md'],
  );

  void writeDangling() => _writeEntry(
    register,
    '2026-01-02-dangling.md',
    slug: 'dangling',
    updates: ['no-such-rule'],
  );

  group('DecisionLintGate', () {
    test('keeps every non-exempt diagnostic in order', () {
      const proposed = DecisionLintDiagnostic(
        ruleId: DecisionLintRules.statusProposed,
        file: 'a.md',
        message: 'this profile never uses proposed',
      );
      final gate = DecisionLintGate(
        DecisionLintResult(
          register: 'docs/decisions',
          diagnostics: const [_localSurface, _rosterSurface, proposed],
        ),
      );

      expect(gate.result.register, 'docs/decisions');
      expect(gate.result.diagnostics, [_localSurface, proposed]);
      expect(gate.exempt, [_rosterSurface]);
      expect(() => gate.exempt.add(_rosterSurface), throwsUnsupportedError);
    });
  });

  group('AC-1 the gate verdict', () {
    test('this repository\'s register is clean under --gate', () async {
      final run = await _standalone([
        'lint',
        '--gate',
        '../../../docs/decisions',
        '--repo-root',
        '../../..',
      ]);

      expect(run.code, 0);
      expect(run.out, 'docs/decisions: clean\n');
      expect(run.err, isEmpty);
    });

    test('a seeded dirty register fails the gate', () async {
      writeRosterRule();
      writeDangling();

      final run = await _standalone(gateArgs());

      expect(run.code, 1);
    });
  });

  group('AC-2 the roster-wide exemption', () {
    setUp(writeRosterRule);

    test('plain lint still reports the roster-marked surface', () async {
      final run = await _standalone(gateArgs(gate: false));

      expect(run.code, 1);
      expect(
        run.out,
        'docs/decisions/2026-01-01-roster-rule.md: [surface.unmatched] '
        '$_rosterMessage\n',
      );
    });

    test('--gate exempts it and counts the exemption', () async {
      final run = await _standalone(gateArgs());

      expect(run.code, 0);
      expect(
        run.out,
        'docs/decisions: clean (1 roster-wide surface(s) exempted)\n',
      );
      expect(run.err, isEmpty);
    });

    test('--gate --json is a valid, clean lint result', () async {
      final run = await _standalone(gateArgs(json: true));
      final decoded = jsonDecode(run.out) as Map<String, Object?>;
      final schema = JsonSchema.create(
        jsonDecode(
              File(
                '../../../schema/lint-result.schema.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>,
      );

      expect(run.code, 0);
      expect(schema.validate(decoded).isValid, isTrue);
      expect(decoded['valid'], isTrue);
      expect(decoded['diagnostics'], isEmpty);
    });
  });

  group('AC-3 every other class stays fatal', () {
    test('DecisionLintRules declares 14 distinct rule ids', () {
      expect(_ruleIds.toSet(), hasLength(14));
    });

    for (final ruleId in _ruleIds) {
      test('$ruleId fails the gate', () async {
        final diagnostic = DecisionLintDiagnostic(
          ruleId: ruleId,
          file: 'docs/decisions/2026-01-01-entry.md',
          message: ruleId == DecisionLintRules.surfaceUnmatched
              ? _localMessage
              : _rosterMessage,
        );
        final run = await _standalone(
          ['lint', '--gate', 'docs/decisions'],
          linter: _FixedLinter(
            DecisionLintResult(
              register: 'docs/decisions',
              diagnostics: [diagnostic],
            ),
          ),
        );

        expect(run.code, 1);
        expect(
          run.out,
          '${diagnostic.file}: [$ruleId] ${diagnostic.message}\n',
        );
      });
    }

    for (final (fixture, ruleId) in [
      ('dangling_register', DecisionLintRules.edgeDanglingLocal),
      ('duplicate_register', DecisionLintRules.identityDuplicateSlug),
      ('graph_register', DecisionLintRules.forceStatus),
      ('proposed_register', DecisionLintRules.statusProposed),
      ('schema_register', DecisionLintRules.entrySchema),
      ('surface_register', DecisionLintRules.surfaceUnmatched),
      ('future_spec_register', DecisionLintRules.specUnsupported),
    ]) {
      test('fixture $fixture fails the gate with [$ruleId]', () async {
        final run = await _standalone([
          'lint',
          '--gate',
          'test/fixtures/$fixture',
          '--repo-root',
          '.',
        ]);

        expect(run.code, 1);
        expect(run.out, contains('[$ruleId]'));
      });
    }
  });

  group('AC-4 parity with memento-engineering tool/lint_register.dart', () {
    const proposedWithRoster = DecisionLintDiagnostic(
      ruleId: DecisionLintRules.statusProposed,
      file: 'docs/decisions/2026-01-03-proposed.md',
      message: _rosterMessage,
    );

    for (final (name, diagnostics, passes) in [
      ('a roster-marked unmatched surface only', [_rosterSurface], true),
      ('a clean register', <DecisionLintDiagnostic>[], true),
      ('a repo-local unmatched surface', [_localSurface], false),
      (
        'a non-surface rule whose message carries roster:',
        [proposedWithRoster],
        false,
      ),
      (
        'a roster-marked and a repo-local unmatched surface',
        [_rosterSurface, _localSurface],
        false,
      ),
    ]) {
      test('$name: ${passes ? 'passes' : 'fails'} in both', () async {
        final result = DecisionLintResult(
          register: 'docs/decisions',
          diagnostics: diagnostics,
        );
        final run = await _standalone([
          'lint',
          '--gate',
          'docs/decisions',
        ], linter: _FixedLinter(result));

        expect(_referenceExit(result) == 0, passes);
        expect(run.code == 0, passes);
      });
    }

    test('a missing register fails in both: 2 there, 1 here', () async {
      register.deleteSync(recursive: true);

      final run = await _standalone(gateArgs());

      expect(_referenceExit(null), 2);
      expect(run.code, 1);
    });
  });

  group('AC-5 actionable output on the right streams', () {
    test('a failing run names each finding on stdout only', () async {
      writeRosterRule();
      writeDangling();

      final run = await _standalone(gateArgs());

      expect(run.code, 1);
      expect(
        run.out,
        'docs/decisions/2026-01-02-dangling.md: [edge.dangling-local] '
        'authored reference "no-such-rule" does not resolve\n',
      );
      expect(run.out, isNot(contains('roster:')));
      expect(run.err, isEmpty);
    });

    test('a missing register is a finding on stdout', () async {
      register.deleteSync(recursive: true);

      final run = await _standalone(gateArgs());

      expect(run.code, 1);
      expect(
        run.out,
        'docs/decisions: [entry.schema] register directory does not exist\n',
      );
      expect(run.err, isEmpty);
    });

    test('--gate without a register path is a usage error', () async {
      final run = await _standalone(['lint', '--gate']);

      expect(run.code, DecisionsCommandRunner.usageExitCode);
      expect(run.code, 64);
      expect(run.err, contains('Expected exactly one register path.'));
      expect(run.out, isEmpty);
    });

    test('the composed host gives the standalone runner\'s result', () async {
      writeRosterRule();
      writeDangling();

      final standalone = await _standalone(gateArgs());
      final grouped = await _grouped(gateArgs());

      expect(grouped.code, standalone.code);
      expect(grouped.out, standalone.out);
    });
  });
}
