import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Records drafts instead of writing them, or refuses with [refusal].
final class FakeDecisionRecorder implements DecisionRecorder {
  FakeDecisionRecorder({this.refusal});

  final String? refusal;
  final drafts = <DecisionDraft>[];
  String? registerPath;
  String? repoRoot;

  @override
  DecisionRecordResult record({
    required String registerPath,
    required String repoRoot,
    required DecisionDraft draft,
  }) {
    this.registerPath = registerPath;
    this.repoRoot = repoRoot;
    drafts.add(draft);
    if (refusal case final message?) throw DecisionRecordException(message);
    return DecisionRecordResult(
      path: '$registerPath/2026-10-24-${draft.slug}.md',
      citation: 'alpha#${draft.slug}',
      nextSteps: [
        for (final target in draft.updates)
          DecisionNextStep(
            kind: DecisionEdgeKind.updates,
            target: target,
            successor: draft.slug,
          ),
      ],
    );
  }
}

const _body = '''
## Context and Problem Statement

Why.

## Decision Outcome

What.
''';

void main() {
  late Directory sandbox;
  late StringBuffer output;
  late StringBuffer error;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decisions-new-command-');
    output = StringBuffer();
    error = StringBuffer();
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Future<int?> run(
    List<String> args, {
    required DecisionRecorder recorder,
    String stdinText = '',
    DecisionInputReader? readInput,
  }) {
    final runner = CommandRunner<int>('decisions', 'fixture')
      ..addCommand(
        DecisionNewCommand(
          recorder: recorder,
          readInput: readInput ?? () => stdinText,
          output: output,
          error: error,
        ),
      );
    return runner.run(['new', ...args]);
  }

  test('maps every flag onto the draft and prints the next steps', () async {
    final recorder = FakeDecisionRecorder();
    final code = await run(
      [
        'a-rule',
        '--title',
        'A rule',
        '--body',
        '-',
        '--surface',
        'lib/**',
        '--surface',
        'README.md',
        '--decision-maker',
        'nico',
        '--decision-maker',
        'agent',
        '--consulted',
        'reviewer',
        '--informed',
        'team',
        '--obsoletes',
        'old-rule',
        '--updates',
        'base-rule',
        '--updates',
        'bravo#their-rule',
        '--bead',
        'dec-abc',
        '--date',
        '2026-10-24',
        '--register',
        'reg',
        '--repo-root',
        'root',
      ],
      recorder: recorder,
      stdinText: _body,
    );

    expect(code, 0);
    expect(recorder.registerPath, 'reg');
    expect(recorder.repoRoot, 'root');
    final draft = recorder.drafts.single;
    expect(draft.slug, 'a-rule');
    expect(draft.title, 'A rule');
    expect(draft.body, _body);
    expect(draft.surfaces, ['lib/**', 'README.md']);
    expect(draft.decisionMakers, ['nico', 'agent']);
    expect(draft.consulted, ['reviewer']);
    expect(draft.informed, ['team']);
    expect(draft.obsoletes, ['old-rule']);
    expect(draft.updates, ['base-rule', 'bravo#their-rule']);
    expect(draft.bead, 'dec-abc');
    expect(draft.date, '2026-10-24');
    expect(
      output.toString(),
      'wrote reg/2026-10-24-a-rule.md\n'
      'alpha#a-rule\n'
      'next: decisions update base-rule --by a-rule\n'
      'next: decisions update bravo#their-rule --by a-rule\n',
    );
    expect(error.toString(), isEmpty);
  });

  test('defaults: no bead, no date, docs/decisions in .', () async {
    final recorder = FakeDecisionRecorder();
    final bodyFile = File(p.join(sandbox.path, 'body.md'))
      ..writeAsStringSync(_body);

    final code = await run([
      'a-rule',
      '--title',
      'A rule',
      '--body',
      bodyFile.path,
      '--surface',
      'lib/**',
      '--decision-maker',
      'nico',
    ], recorder: recorder);

    expect(code, 0);
    expect(recorder.registerPath, 'docs/decisions');
    expect(recorder.repoRoot, '.');
    final draft = recorder.drafts.single;
    expect(draft.body, _body);
    expect(draft.bead, isNull);
    expect(draft.date, isNull);
    expect(draft.consulted, isEmpty);
  });

  test('a refusal exits 1 on the error sink', () async {
    final recorder = FakeDecisionRecorder(refusal: 'slug collision');

    final code = await run([
      'a-rule',
      '--title',
      'A rule',
      '--body',
      '-',
      '--surface',
      'lib/**',
      '--decision-maker',
      'nico',
    ], recorder: recorder);

    expect(code, 1);
    expect(output.toString(), isEmpty);
    expect(error.toString(), 'error: slug collision\n');
  });

  test('an unreadable body exits 1 before recording', () async {
    final recorder = FakeDecisionRecorder();

    final code = await run([
      'a-rule',
      '--title',
      'A rule',
      '--body',
      p.join(sandbox.path, 'missing.md'),
      '--surface',
      'lib/**',
      '--decision-maker',
      'nico',
    ], recorder: recorder);

    expect(code, 1);
    expect(recorder.drafts, isEmpty);
    expect(error.toString(), startsWith('error: cannot read body'));
  });

  test('a body on stdin that is not UTF-8 exits 1 before recording', () async {
    final recorder = FakeDecisionRecorder();

    final code = await run(
      [
        'a-rule',
        '--title',
        'A rule',
        '--body',
        '-',
        '--surface',
        'lib/**',
        '--decision-maker',
        'nico',
      ],
      recorder: recorder,
      readInput: () => utf8.decode([0xff, 0xfe]),
    );

    expect(code, 1);
    expect(recorder.drafts, isEmpty);
    expect(error.toString(), startsWith('error: cannot read body -'));
  });

  group('a missing required input is a usage error', () {
    const complete = [
      'a-rule',
      '--title',
      'A rule',
      '--body',
      '-',
      '--surface',
      'lib/**',
      '--decision-maker',
      'nico',
    ];
    final cases = <String, List<String>>{
      'slug': complete.sublist(1),
      'title': [...complete]..removeRange(1, 3),
      'body': [...complete]..removeRange(3, 5),
      'surface': [...complete]..removeRange(5, 7),
      'decision-maker': [...complete]..removeRange(7, 9),
    };
    for (final MapEntry(key: missing, value: args) in cases.entries) {
      test(missing, () async {
        final recorder = FakeDecisionRecorder();

        await expectLater(
          run(args, recorder: recorder),
          throwsA(isA<UsageException>()),
        );
        expect(recorder.drafts, isEmpty);
      });
    }
  });

  test('--help is bounded and names the required inputs', () async {
    final help = StringBuffer();
    final code = await DecisionsCommandRunner(
      output: help,
    ).run(['new', '--help']);

    expect(code, 0);
    final text = help.toString();
    expect(text, contains('Usage: decisions new <slug>'));
    for (final flag in ['--title', '--body', '--surface', '--decision-maker']) {
      expect(text, contains(flag));
    }
    // The contract: exit codes, refusal semantics, and the next steps.
    for (final clause in [
      'Exits 0 when written',
      'Exits 1 when refused, having written nothing',
      'usage error',
      '"next:" line',
    ]) {
      expect(text, contains(clause));
    }
    expect(text.split('\n').length, lessThan(40));
  });

  test('the standalone runner writes a clean entry end to end', () async {
    final repoRoot = p.join(sandbox.path, 'alpha');
    File(p.join(repoRoot, 'lib', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
    final bodyFile = File(p.join(sandbox.path, 'body.md'))
      ..writeAsStringSync(_body);
    final register = p.join(repoRoot, 'docs', 'decisions');

    final code = await DecisionsCommandRunner(output: output, error: error)
        .run([
          'new',
          'a-rule',
          '--title',
          'A rule',
          '--body',
          bodyFile.path,
          '--surface',
          'lib/fixture.dart',
          '--decision-maker',
          'nico',
          '--date',
          '2026-10-24',
          '--register',
          register,
          '--repo-root',
          repoRoot,
        ]);

    expect(error.toString(), isEmpty);
    expect(code, 0);
    final path = p.join(register, '2026-10-24-a-rule.md');
    expect(output.toString(), 'wrote $path\nalpha#a-rule\n');
    expect(
      const DecisionLintService()
          .lint(registerPath: register, repoRoot: repoRoot)
          .isClean,
      isTrue,
    );

    final again = StringBuffer();
    final collision = await DecisionsCommandRunner(output: output, error: again)
        .run([
          'new',
          'a-rule',
          '--title',
          'A rule',
          '--body',
          bodyFile.path,
          '--surface',
          'lib/fixture.dart',
          '--decision-maker',
          'nico',
          '--register',
          register,
          '--repo-root',
          repoRoot,
        ]);
    expect(collision, 1);
    expect(again.toString(), contains('already recorded in $path'));
  });
}
