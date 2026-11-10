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
    // The contract: exit codes, streams, refusal semantics, next steps.
    final prose = text.replaceAll('\n', ' ');
    for (final clause in [
      'Exits 0 when written, printing on stdout',
      'Exits 1 when refused, having written nothing, with the reason on '
          'stderr',
      'usage error',
      '"next:" line',
    ]) {
      expect(prose, contains(clause));
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

  test('the closing lint names a pending force request on another entry and '
      'nothing on the new one', () async {
    final repoRoot = p.join(sandbox.path, 'alpha');
    File(p.join(repoRoot, 'lib', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
    final bodyFile = File(p.join(sandbox.path, 'body.md'))
      ..writeAsStringSync(_body);
    final register = p.join(repoRoot, 'docs', 'decisions');

    Future<int> record(
      String slug,
      StringBuffer errors, [
      List<String> edges = const [],
    ]) => DecisionsCommandRunner(output: output, error: errors).run([
      'new',
      slug,
      '--title',
      'The $slug',
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
      ...edges,
    ]);

    expect(await record('b-rule', error), 0);
    // A's printed next: line is deliberately not run, leaving the
    // force.updated-by back-edge pending on B.
    expect(await record('a-rule', error, ['--updates', 'b-rule']), 0);
    expect(error.toString(), isEmpty);
    final aFile = File(p.join(register, '2026-10-24-a-rule.md'));
    final bFile = File(p.join(register, '2026-10-24-b-rule.md'));
    final aBefore = aFile.readAsStringSync();
    final bBefore = bFile.readAsStringSync();

    final cErrors = StringBuffer();
    expect(await record('c-rule', cErrors), 0);
    expect(cErrors.toString(), isEmpty);
    expect(File(p.join(register, '2026-10-24-c-rule.md')).existsSync(), isTrue);
    expect(aFile.readAsStringSync(), aBefore);
    expect(bFile.readAsStringSync(), bBefore);

    final lintOutput = StringBuffer();
    final lintCode = await DecisionsCommandRunner(
      output: lintOutput,
      error: StringBuffer(),
    ).run(['lint', register, '--repo-root', repoRoot, '--json']);
    expect(lintCode, 1);
    final result = jsonDecode(lintOutput.toString()) as Map<String, Object?>;
    final diagnostics = (result['diagnostics']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(diagnostics, isNotEmpty);
    for (final diagnostic in diagnostics) {
      final file = p.basename(diagnostic['file']! as String);
      expect(file, '2026-10-24-b-rule.md', reason: '$diagnostic');
      expect(
        diagnostic['ruleId'],
        DecisionLintRules.forceUpdatedBy,
        reason: '$diagnostic',
      );
      expect(
        file,
        isNot(anyOf('2026-10-24-a-rule.md', '2026-10-24-c-rule.md')),
      );
    }
  });

  group('--max-slug-length', () {
    final longSlug = '${'a' * 59}-${'b' * 60}';
    late String repoRoot;
    late String register;
    late String bodyPath;

    setUp(() {
      repoRoot = p.join(sandbox.path, 'alpha');
      register = p.join(repoRoot, 'docs', 'decisions');
      File(p.join(repoRoot, 'README.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# fixture\n');
      bodyPath = (File(
        p.join(sandbox.path, 'body.md'),
      )..writeAsStringSync(_body)).path;
    });

    Future<int> runNew(List<String> extra, {String slug = ''}) =>
        DecisionsCommandRunner(
          output: output,
          error: error,
          registerPaths: () => [register],
        ).run([
          'new',
          slug.isEmpty ? longSlug : slug,
          '--title',
          'A long rule',
          '--body',
          bodyPath,
          '--surface',
          'README.md',
          '--decision-maker',
          'nico',
          '--date',
          '2026-11-05',
          '--register',
          register,
          '--repo-root',
          repoRoot,
          ...extra,
        ]);

    test('writes a slug longer than the default under the flag', () async {
      expect(await runNew(['--max-slug-length', '160']), 0);
      expect(error.toString(), isEmpty);
      final path = p.join(register, '2026-11-05-$longSlug.md');
      expect(output.toString(), startsWith('wrote $path\n'));
      expect(parseEntry(path, maxSlugLength: 160).slug, longSlug);
    });

    test('refuses it without the flag, naming the default', () async {
      expect(await runNew(const []), 1);
      expect(
        error.toString(),
        'error: invalid slug "$longSlug"; use at most 80 characters of '
        'lowercase kebab-case\n',
      );
      expect(output.toString(), isEmpty);
      expect(Directory(register).existsSync(), isFalse);
    });

    test('refuses it under a smaller flag, naming that limit', () async {
      expect(await runNew(['--max-slug-length', '100']), 1);
      expect(error.toString(), contains('use at most 100 characters'));
      expect(Directory(register).existsSync(), isFalse);
    });

    test('carries the flag into each next: line', () async {
      File(p.join(register, '2026-11-01-base-rule.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
---
status: accepted
date: 2026-11-01
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: "base-rule"
  surfaces:
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Base rule

$_body''');

      expect(
        await runNew(['--updates', 'base-rule', '--max-slug-length', '160']),
        0,
      );
      expect(error.toString(), isEmpty);
      expect(
        output.toString(),
        contains(
          'next: decisions update base-rule --by $longSlug '
          '--register $register --repo-root $repoRoot '
          '--max-slug-length 160\n',
        ),
      );
    });
  });
}
