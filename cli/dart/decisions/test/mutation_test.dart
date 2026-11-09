import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late Directory register;
  const service = DecisionMutationService();
  const linter = DecisionLintService();

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decision-mutation-test-');
    register = Directory(p.join(sandbox.path, 'docs', 'decisions'))
      ..createSync(recursive: true);
    File(p.join(sandbox.path, 'lib', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
    File(p.join(sandbox.path, 'src', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  group('resurface service', () {
    late File alpha;
    late File beta;
    late File gamma;

    setUp(() {
      (:alpha, :beta, :gamma) = _writeResurfaceFixture(register);
    });

    List<String> resurface({
      String from = 'lib/**',
      String to = 'src/**',
      List<String> entries = const [],
      DecisionLinter? linter,
    }) => DecisionResurfaceService(linter: linter).resurface(
      registerPath: register.path,
      repoRoot: sandbox.path,
      from: from,
      to: to,
      entries: entries,
    );

    test('rewrites the one surface in every carrier, byte for byte', () {
      final alphaBefore = alpha.readAsStringSync();
      final betaBefore = beta.readAsStringSync();
      final gammaBefore = gamma.readAsBytesSync();

      expect(resurface(), ['alpha', 'beta']);

      expect(
        alpha.readAsStringSync(),
        alphaBefore.replaceFirst('"lib/**"', '"src/**"'),
      );
      expect(
        beta.readAsStringSync(),
        betaBefore.replaceFirst('"lib/**"', '"src/**"'),
      );
      expect(gamma.readAsBytesSync(), orderedEquals(gammaBefore));
      expect(parseEntry(alpha.path).surfaces, ['src/**']);
      expect(parseEntry(beta.path).surfaces, ['docs/**', 'src/**']);
    });

    test('named entries limit the rewrite', () {
      final betaBefore = beta.readAsBytesSync();

      expect(resurface(entries: const ['alpha']), ['alpha']);
      expect(parseEntry(alpha.path).surfaces, ['src/**']);
      expect(beta.readAsBytesSync(), orderedEquals(betaBefore));

      expect(resurface(from: 'src/**', to: 'lib/**'), ['alpha']);
      expect(resurface(entries: const ['beta', 'alpha', 'beta']), [
        'alpha',
        'beta',
      ]);
      expect(parseEntry(alpha.path).surfaces, ['src/**']);
      expect(parseEntry(beta.path).surfaces, ['docs/**', 'src/**']);
    });

    final refusals =
        <
          String,
          ({
            String from,
            String to,
            List<String> entries,
            String Function(String root) message,
          })
        >{
          'the same glob': (
            from: 'lib/**',
            to: 'lib/**',
            entries: const [],
            message: (_) => '--from and --to are the same glob "lib/**"',
          ),
          'an empty glob': (
            from: '',
            to: 'src/**',
            entries: const [],
            message: (_) => '--from and --to must each be a non-empty glob',
          ),
          'no carrier': (
            from: 'nothing/**',
            to: 'src/**',
            entries: const [],
            message: (_) => 'no entry carries surface "nothing/**"',
          ),
          'an unmatched --to': (
            from: 'lib/**',
            to: 'missing/**',
            entries: const [],
            message: (root) =>
                'surface "missing/**" matched no filesystem entry under '
                '$root',
          ),
          'an unknown entry': (
            from: 'lib/**',
            to: 'src/**',
            entries: const ['alpha', 'nope'],
            message: (_) => 'unknown entry slug "nope"',
          ),
          'an entry without --from': (
            from: 'lib/**',
            to: 'src/**',
            entries: const ['gamma'],
            message: (_) => 'entry "gamma" carries no surface "lib/**"',
          ),
        };
    for (final MapEntry(key: name, value: refusal) in refusals.entries) {
      test('refuses $name, writing nothing', () {
        final before = _registerBytes(register);
        expect(
          () => resurface(
            from: refusal.from,
            to: refusal.to,
            entries: refusal.entries,
          ),
          throwsA(
            isA<DecisionMutationException>().having(
              (error) => error.message,
              'message',
              refusal.message(sandbox.path),
            ),
          ),
        );
        expect(_registerBytes(register), before);
      });
    }

    test('refuses a rule the candidate gains on a rewritten entry', () {
      final before = _registerBytes(register);
      expect(
        () => resurface(linter: _CandidateOnlyLinter(register.path)),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            'candidate register is not clean: '
                'docs/decisions/2026-01-01-alpha.md [fixture.rule]',
          ),
        ),
      );
      expect(_registerBytes(register), before);
    });

    test('a fold leaves one surface and every other field as it was', () {
      final delta = _writeEntry(
        register,
        day: 4,
        slug: 'delta',
        surfaces: const ['lib/**', 'src/**'],
      );
      final bodyBefore = _bodyBytes(delta);
      final entryBefore = parseEntry(delta.path);
      final authoredBefore = _authored(entryBefore)..remove('surfaces');

      expect(resurface(), ['alpha', 'beta', 'delta']);

      final changed = parseEntry(delta.path);
      expect(changed.surfaces, ['src/**']);
      expect(_bodyBytes(delta), orderedEquals(bodyBefore));
      expect(_authored(changed)..remove('surfaces'), authoredBefore);
      expect(changed.status, entryBefore.status);
      expect(changed.cachedObsoletedBy, entryBefore.cachedObsoletedBy);
      expect(changed.cachedUpdatedBy, entryBefore.cachedUpdatedBy);
    });

    test('rewrites a superseded entry and keeps its force lines', () {
      final superseded = _writeEntry(
        register,
        day: 4,
        slug: 'old-rule',
        status: 'superseded by alpha',
        obsoletedBy: 'alpha',
      );
      List<String> forceLines(File file) => file
          .readAsLinesSync()
          .where(
            (line) =>
                line.startsWith('status:') ||
                line.startsWith('  obsoleted-by:'),
          )
          .toList();
      final forceBefore = forceLines(superseded);

      expect(resurface(entries: const ['old-rule']), ['old-rule']);

      expect(parseEntry(superseded.path).surfaces, ['src/**']);
      expect(forceLines(superseded), forceBefore);
      expect(forceBefore, [
        'status: superseded by alpha',
        '  obsoleted-by: alpha',
      ]);
    });

    test('a roster-wide --to is exempt from the checkout check', () {
      final wide = _writeEntry(
        register,
        day: 4,
        slug: 'wide-rule',
        surface: 'roster:OLD.md',
      );
      expect(File(p.join(sandbox.path, 'CLAUDE.md')).existsSync(), isFalse);

      expect(resurface(from: 'roster:OLD.md', to: 'roster:CLAUDE.md'), [
        'wide-rule',
      ]);
      expect(parseEntry(wide.path).surfaces, ['roster:CLAUDE.md']);
    });

    test('lint over a rewritten entry is never dirtier', () {
      Directory(p.join(sandbox.path, 'lib')).deleteSync(recursive: true);
      _writeEntry(register, day: 4, slug: 'unrelated', surface: 'gone/**');
      const lintService = DecisionLintService();
      Map<String, List<Object>> byFile() {
        final result = lintService.lint(
          registerPath: register.path,
          repoRoot: sandbox.path,
        );
        final grouped = <String, List<Object>>{};
        for (final diagnostic in result.diagnostics) {
          grouped
              .putIfAbsent(diagnostic.file, () => [])
              .add(diagnostic.toJson());
        }
        return grouped;
      }

      const alphaPath = 'docs/decisions/2026-01-01-alpha.md';
      const betaPath = 'docs/decisions/2026-01-02-beta.md';
      const unrelatedPath = 'docs/decisions/2026-01-04-unrelated.md';
      final before = byFile();
      bool unmatched(Object json) =>
          (json as Map)['ruleId'] == DecisionLintRules.surfaceUnmatched;
      expect(before[alphaPath]!.where(unmatched), isNotEmpty);
      expect(before[betaPath]!.where(unmatched), isNotEmpty);
      expect(before[unrelatedPath], isNotEmpty);

      expect(resurface(), ['alpha', 'beta']);

      final after = byFile();
      for (final path in [alphaPath, betaPath]) {
        final rewritten = after[path] ?? const <Object>[];
        final prior = before[path]!.map(jsonEncode).toSet();
        expect(rewritten.map(jsonEncode).toSet().difference(prior), isEmpty);
        expect(rewritten.where(unmatched), isEmpty);
      }
      expect(
        jsonEncode(after[unrelatedPath]),
        jsonEncode(before[unrelatedPath]),
      );
    });
  });

  group('resurface command', () {
    late File alpha;
    late File beta;
    late StringBuffer output;
    late StringBuffer error;

    setUp(() {
      (:alpha, :beta, gamma: _) = _writeResurfaceFixture(register);
      output = StringBuffer();
      error = StringBuffer();
    });

    Future<int> run(List<String> args) => DecisionsCommandRunner(
      output: output,
      error: error,
    ).run(['resurface', ...args]);

    List<String> scoped(List<String> args) => [
      ...args,
      '--register',
      register.path,
      '--repo-root',
      sandbox.path,
    ];

    test('rewrites every carrier and prints their slugs', () async {
      final alphaBefore = alpha.readAsStringSync();
      final betaBefore = beta.readAsStringSync();

      expect(await run(scoped(['--from', 'lib/**', '--to', 'src/**'])), 0);

      expect(output.toString(), 'alpha\nbeta\n');
      expect(error.toString(), isEmpty);
      expect(
        alpha.readAsStringSync(),
        alphaBefore.replaceFirst('"lib/**"', '"src/**"'),
      );
      expect(
        beta.readAsStringSync(),
        betaBefore.replaceFirst('"lib/**"', '"src/**"'),
      );
    });

    test('--entry limits the rewrite, and repeats', () async {
      final betaBefore = beta.readAsBytesSync();

      expect(
        await run(
          scoped(['--from', 'lib/**', '--to', 'src/**', '--entry', 'alpha']),
        ),
        0,
      );
      expect(output.toString(), 'alpha\n');
      expect(beta.readAsBytesSync(), orderedEquals(betaBefore));

      output.clear();
      expect(
        await run(
          scoped(['--from', 'src/**', '--to', 'lib/**', '--entry', 'alpha']),
        ),
        0,
      );
      output.clear();
      expect(
        await run(
          scoped([
            '--from',
            'lib/**',
            '--to',
            'src/**',
            '--entry',
            'alpha',
            '--entry',
            'beta',
          ]),
        ),
        0,
      );
      expect(output.toString(), 'alpha\nbeta\n');
      expect(error.toString(), isEmpty);
    });

    final refusals = <String, ({List<String> args, String reason})>{
      'the same glob': (
        args: ['--from', 'lib/**', '--to', 'lib/**'],
        reason: '--from and --to are the same glob "lib/**"',
      ),
      'a --from no entry carries': (
        args: ['--from', 'nothing/**', '--to', 'src/**'],
        reason: 'no entry carries surface "nothing/**"',
      ),
      'an unmatched --to': (
        args: ['--from', 'lib/**', '--to', 'missing/**'],
        reason: 'surface "missing/**" matched no filesystem entry under',
      ),
      'an unknown --entry': (
        args: ['--from', 'lib/**', '--to', 'src/**', '--entry', 'nope'],
        reason: 'unknown entry slug "nope"',
      ),
      'an --entry without --from': (
        args: ['--from', 'lib/**', '--to', 'src/**', '--entry', 'gamma'],
        reason: 'entry "gamma" carries no surface "lib/**"',
      ),
      'a missing --from': (
        args: ['--to', 'src/**'],
        reason: '--from requires a glob',
      ),
      'an empty --from': (
        args: ['--from', '', '--to', 'src/**'],
        reason: '--from requires a glob',
      ),
      'a missing --to': (
        args: ['--from', 'lib/**'],
        reason: '--to requires a glob',
      ),
      'a positional argument': (
        args: ['alpha', '--from', 'lib/**', '--to', 'src/**'],
        reason: 'resurface takes no positional arguments',
      ),
    };
    for (final MapEntry(key: name, value: refusal) in refusals.entries) {
      test('refuses $name with exit 1, writing nothing', () async {
        final before = _registerBytes(register);

        expect(await run(scoped(refusal.args)), 1);

        expect(output.toString(), isEmpty);
        expect(error.toString(), startsWith('error: '));
        expect(error.toString(), contains(refusal.reason));
        expect(_registerBytes(register), before);
      });
    }
  });

  test('obsolete changes only its force cache and leaves lint clean', () {
    final target = _writeEntry(register, day: 1, slug: 'old-rule');
    _writeEntry(
      register,
      day: 2,
      slug: 'replacement',
      obsoletes: const ['old-rule'],
    );
    final bodyBefore = _bodyBytes(target);
    final authoredBefore = _authored(parseEntry(target.path));

    expect(parseEntry(target.path).status, 'accepted');
    service.obsolete(
      registerPath: register.path,
      repoRoot: '.',
      target: 'old-rule',
      successor: 'replacement',
    );

    final changed = parseEntry(target.path);
    expect(changed.status, 'superseded by replacement');
    expect(changed.cachedObsoletedBy, 'replacement');
    expect(changed.cachedUpdatedBy, isEmpty);
    expect(_bodyBytes(target), orderedEquals(bodyBefore));
    expect(_authored(changed), authoredBefore);
    _expectClean(linter, register);
  });

  test('update keeps accepted force, derives cache, and leaves lint clean', () {
    final target = _writeEntry(register, day: 1, slug: 'base-rule');
    _writeEntry(
      register,
      day: 2,
      slug: 'first-amendment',
      updates: const ['base-rule'],
    );
    _writeEntry(
      register,
      day: 3,
      slug: 'second-amendment',
      updates: const ['base-rule'],
    );
    final bodyBefore = _bodyBytes(target);
    final authoredBefore = _authored(parseEntry(target.path));

    service.update(
      registerPath: register.path,
      repoRoot: '.',
      target: 'base-rule',
      successor: 'second-amendment',
    );

    final changed = parseEntry(target.path);
    expect(changed.status, 'accepted');
    expect(
      changed.cachedUpdatedBy,
      orderedEquals(['first-amendment', 'second-amendment']),
    );
    expect(changed.cachedObsoletedBy, isNull);
    expect(_bodyBytes(target), orderedEquals(bodyBefore));
    expect(_authored(changed), authoredBefore);
    _expectClean(linter, register);
  });

  test(
    'update accepts roster-wide surfaces and derives the cached back-edge',
    () {
      final target = _writeEntry(
        register,
        day: 1,
        slug: 'base-rule',
        surface: 'roster:CLAUDE.md',
      );
      final successor = _writeEntry(
        register,
        day: 2,
        slug: 'amendment',
        surface: 'roster:CLAUDE.md',
        updates: const ['base-rule'],
      );
      final targetBodyBefore = _bodyBytes(target);
      final targetAuthoredBefore = _authored(parseEntry(target.path));
      final successorBefore = successor.readAsBytesSync();

      service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'base-rule',
        successor: 'amendment',
      );

      final changed = parseEntry(target.path);
      expect(changed.status, 'accepted');
      expect(changed.cachedUpdatedBy, orderedEquals(['amendment']));
      expect(changed.cachedObsoletedBy, isNull);
      expect(_bodyBytes(target), orderedEquals(targetBodyBefore));
      expect(_authored(changed), targetAuthoredBefore);
      expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
    },
  );

  test('obsolete and vacate accept roster-wide surfaces through the shared '
      'precondition', () {
    final obsoleteTarget = _writeEntry(
      register,
      day: 1,
      slug: 'old-rule',
      surface: 'roster:CLAUDE.md',
    );
    final replacement = _writeEntry(
      register,
      day: 2,
      slug: 'replacement',
      surface: 'roster:CLAUDE.md',
      obsoletes: const ['old-rule'],
    );
    final vacateTarget = _writeEntry(
      register,
      day: 3,
      slug: 'withdrawn-rule',
      surface: 'roster:CLAUDE.md',
    );
    final vacateSuccessor = _writeEntry(
      register,
      day: 4,
      slug: 'no-rule-governs',
      surface: 'roster:CLAUDE.md',
    );
    final obsoleteBodyBefore = _bodyBytes(obsoleteTarget);
    final obsoleteAuthoredBefore = _authored(parseEntry(obsoleteTarget.path));
    final replacementBefore = replacement.readAsBytesSync();
    final vacateBodyBefore = _bodyBytes(vacateTarget);
    final vacateAuthoredBefore = _authored(parseEntry(vacateTarget.path));
    final vacateSuccessorBefore = vacateSuccessor.readAsBytesSync();

    service.obsolete(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'old-rule',
      successor: 'replacement',
    );
    service.vacate(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'withdrawn-rule',
      successor: 'no-rule-governs',
    );

    final obsoleted = parseEntry(obsoleteTarget.path);
    expect(obsoleted.status, 'superseded by replacement');
    expect(obsoleted.cachedObsoletedBy, 'replacement');
    expect(obsoleted.cachedUpdatedBy, isEmpty);
    expect(_bodyBytes(obsoleteTarget), orderedEquals(obsoleteBodyBefore));
    expect(_authored(obsoleted), obsoleteAuthoredBefore);
    expect(replacement.readAsBytesSync(), orderedEquals(replacementBefore));

    final vacated = parseEntry(vacateTarget.path);
    expect(vacated.status, 'deprecated');
    expect(vacated.cachedObsoletedBy, isNull);
    expect(vacated.cachedUpdatedBy, isEmpty);
    expect(_bodyBytes(vacateTarget), orderedEquals(vacateBodyBefore));
    expect(_authored(vacated), vacateAuthoredBefore);
    expect(
      vacateSuccessor.readAsBytesSync(),
      orderedEquals(vacateSuccessorBefore),
    );
  });

  test('update refuses a dirty touched target without writing', () {
    final target = _writeEntry(
      register,
      day: 1,
      slug: 'base-rule',
      surface: 'missing/**',
    );
    final successor = _writeEntry(
      register,
      day: 2,
      slug: 'amendment',
      updates: const ['base-rule'],
    );
    final targetBefore = target.readAsBytesSync();
    final successorBefore = successor.readAsBytesSync();

    expect(
      () => service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'base-rule',
        successor: 'amendment',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          'candidate register is not clean: '
              'docs/decisions/2026-01-01-base-rule.md '
              '[surface.unmatched]',
        ),
      ),
    );
    expect(target.readAsBytesSync(), orderedEquals(targetBefore));
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
  });

  test('obsolete takes a target whose surfaces match nothing out of force', () {
    final target = _writeEntry(
      register,
      day: 1,
      slug: 'old-rule',
      surface: 'missing/**',
    );
    _writeEntry(
      register,
      day: 2,
      slug: 'replacement',
      obsoletes: const ['old-rule'],
    );

    service.obsolete(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'old-rule',
      successor: 'replacement',
    );

    final changed = parseEntry(target.path);
    expect(changed.status, 'superseded by replacement');
    expect(changed.cachedObsoletedBy, 'replacement');
    _expectClean(linter, register);
  });

  test('vacate takes a target whose surfaces match nothing out of force', () {
    final target = _writeEntry(
      register,
      day: 1,
      slug: 'withdrawn-rule',
      surface: 'missing/**',
    );
    _writeEntry(register, day: 2, slug: 'no-rule-governs');

    service.vacate(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'withdrawn-rule',
      successor: 'no-rule-governs',
    );

    expect(parseEntry(target.path).status, 'deprecated');
    _expectClean(linter, register);
  });

  test('obsolete still refuses a successor in force whose surfaces match '
      'nothing', () {
    final target = _writeEntry(register, day: 1, slug: 'old-rule');
    final successor = _writeEntry(
      register,
      day: 2,
      slug: 'replacement',
      surface: 'missing/**',
      obsoletes: const ['old-rule'],
    );
    final targetBefore = target.readAsBytesSync();
    final successorBefore = successor.readAsBytesSync();

    expect(
      () => service.obsolete(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'old-rule',
        successor: 'replacement',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          'candidate register is not clean: '
              'docs/decisions/2026-01-02-replacement.md '
              '[surface.unmatched]',
        ),
      ),
    );
    expect(target.readAsBytesSync(), orderedEquals(targetBefore));
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
  });

  test('update ignores diagnostics on unrelated entries', () {
    final target = _writeEntry(register, day: 1, slug: 'base-rule');
    final successor = _writeEntry(
      register,
      day: 2,
      slug: 'amendment',
      updates: const ['base-rule'],
    );
    final unrelated = _writeEntry(
      register,
      day: 3,
      slug: 'unrelated-rule',
      surface: 'missing/**',
    );
    final unrelatedSuccessor = _writeEntry(
      register,
      day: 4,
      slug: 'unrelated-amendment',
      surface: 'missing/**',
      updates: const ['unrelated-rule'],
    );
    final successorBefore = successor.readAsBytesSync();
    final unrelatedBefore = unrelated.readAsBytesSync();
    final unrelatedSuccessorBefore = unrelatedSuccessor.readAsBytesSync();

    service.update(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'base-rule',
      successor: 'amendment',
    );

    expect(
      parseEntry(target.path).cachedUpdatedBy,
      orderedEquals(['amendment']),
    );
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
    expect(unrelated.readAsBytesSync(), orderedEquals(unrelatedBefore));
    expect(
      unrelatedSuccessor.readAsBytesSync(),
      orderedEquals(unrelatedSuccessorBefore),
    );
    final remaining = linter.lint(
      registerPath: register.path,
      repoRoot: sandbox.path,
    );
    expect(
      remaining.diagnostics.map((diagnostic) => diagnostic.ruleId).toSet(),
      containsAll({
        DecisionLintRules.forceUpdatedBy,
        DecisionLintRules.surfaceUnmatched,
      }),
    );
  });

  test('refusal names each dirty touched entry path', () {
    final target = _writeEntry(
      register,
      day: 1,
      slug: 'base-rule',
      surface: 'missing-target/**',
    );
    final successor = _writeEntry(
      register,
      day: 2,
      slug: 'amendment',
      surface: 'missing-successor/**',
      updates: const ['base-rule'],
    );
    _writeEntry(
      register,
      day: 3,
      slug: 'amendment-two',
      updates: const ['amendment'],
    );
    final targetBefore = target.readAsBytesSync();
    final successorBefore = successor.readAsBytesSync();

    expect(
      () => service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'base-rule',
        successor: 'amendment',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          'candidate register is not clean: '
              'docs/decisions/2026-01-01-base-rule.md '
              '[surface.unmatched]; '
              'docs/decisions/2026-01-02-amendment.md '
              '[surface.unmatched]',
        ),
      ),
    );
    expect(target.readAsBytesSync(), orderedEquals(targetBefore));
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
  });

  test('obsolete ignores diagnostics on unrelated entries', () {
    final target = _writeEntry(register, day: 1, slug: 'old-rule');
    final successor = _writeEntry(
      register,
      day: 2,
      slug: 'replacement',
      obsoletes: const ['old-rule'],
    );
    final unrelated = _writeEntry(
      register,
      day: 3,
      slug: 'unrelated-rule',
      surface: 'missing/**',
    );
    _writeEntry(
      register,
      day: 4,
      slug: 'unrelated-amendment',
      surface: 'missing/**',
      updates: const ['unrelated-rule'],
    );
    final successorBefore = successor.readAsBytesSync();
    final unrelatedBefore = unrelated.readAsBytesSync();

    service.obsolete(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'old-rule',
      successor: 'replacement',
    );

    final changed = parseEntry(target.path);
    expect(changed.status, 'superseded by replacement');
    expect(changed.cachedObsoletedBy, 'replacement');
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
    expect(unrelated.readAsBytesSync(), orderedEquals(unrelatedBefore));
  });

  test('vacate ignores diagnostics on unrelated entries', () {
    final target = _writeEntry(register, day: 1, slug: 'withdrawn-rule');
    final successor = _writeEntry(register, day: 2, slug: 'no-rule-governs');
    final unrelated = _writeEntry(
      register,
      day: 3,
      slug: 'unrelated-rule',
      surface: 'missing/**',
    );
    _writeEntry(
      register,
      day: 4,
      slug: 'unrelated-amendment',
      surface: 'missing/**',
      updates: const ['unrelated-rule'],
    );
    final successorBefore = successor.readAsBytesSync();
    final unrelatedBefore = unrelated.readAsBytesSync();

    service.vacate(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'withdrawn-rule',
      successor: 'no-rule-governs',
    );

    expect(parseEntry(target.path).status, 'deprecated');
    expect(successor.readAsBytesSync(), orderedEquals(successorBefore));
    expect(unrelated.readAsBytesSync(), orderedEquals(unrelatedBefore));
  });

  test('sequential updates settle a dirty backlog', () {
    final targets = [
      _writeEntry(register, day: 1, slug: 'target-one'),
      _writeEntry(register, day: 3, slug: 'target-two'),
      _writeEntry(register, day: 5, slug: 'target-three'),
    ];
    _writeEntry(
      register,
      day: 2,
      slug: 'amendment-one',
      updates: const ['target-one'],
    );
    _writeEntry(
      register,
      day: 4,
      slug: 'amendment-two',
      updates: const ['target-two'],
    );
    _writeEntry(
      register,
      day: 6,
      slug: 'amendment-three',
      updates: const ['target-three'],
    );
    expect(
      linter
          .lint(registerPath: register.path, repoRoot: sandbox.path)
          .diagnostics
          .where(
            (diagnostic) =>
                diagnostic.ruleId == DecisionLintRules.forceUpdatedBy,
          ),
      hasLength(3),
    );

    for (final (target, successor) in [
      ('target-one', 'amendment-one'),
      ('target-two', 'amendment-two'),
      ('target-three', 'amendment-three'),
    ]) {
      service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: target,
        successor: successor,
      );
    }

    expect(
      parseEntry(targets[0].path).cachedUpdatedBy,
      orderedEquals(['amendment-one']),
    );
    expect(
      parseEntry(targets[1].path).cachedUpdatedBy,
      orderedEquals(['amendment-two']),
    );
    expect(
      parseEntry(targets[2].path).cachedUpdatedBy,
      orderedEquals(['amendment-three']),
    );
    final result = linter.lint(
      registerPath: register.path,
      repoRoot: sandbox.path,
    );
    expect(result.isClean, isTrue, reason: '${result.toJson()}');
  });

  test('sequential updates settle a chained dirty backlog', () {
    final (:alpha, :beta, :gamma) = _writeChainedBacklog(register);
    expect(
      linter
          .lint(registerPath: register.path, repoRoot: sandbox.path)
          .diagnostics
          .where(
            (diagnostic) =>
                diagnostic.ruleId == DecisionLintRules.forceUpdatedBy,
          ),
      hasLength(3),
    );

    for (final (target, successor) in [
      ('alpha', 'beta'),
      ('beta', 'gamma'),
      ('gamma', 'alpha'),
    ]) {
      service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: target,
        successor: successor,
      );
    }

    expect(parseEntry(alpha.path).cachedUpdatedBy, orderedEquals(['beta']));
    expect(parseEntry(beta.path).cachedUpdatedBy, orderedEquals(['gamma']));
    expect(parseEntry(gamma.path).cachedUpdatedBy, orderedEquals(['alpha']));
    final result = linter.lint(
      registerPath: register.path,
      repoRoot: sandbox.path,
    );
    expect(result.isClean, isTrue, reason: '${result.toJson()}');
  });

  test('successor force.updated-by exemption retains other successor '
      'diagnostics', () {
    final (:alpha, :beta, :gamma) = _writeChainedBacklog(
      register,
      betaSurface: 'missing-successor/**',
    );
    final alphaBefore = alpha.readAsBytesSync();
    final betaBefore = beta.readAsBytesSync();
    final gammaBefore = gamma.readAsBytesSync();

    expect(
      () => service.update(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'alpha',
        successor: 'beta',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          'candidate register is not clean: '
              'docs/decisions/2026-01-02-beta.md [surface.unmatched]',
        ),
      ),
    );
    expect(alpha.readAsBytesSync(), orderedEquals(alphaBefore));
    expect(beta.readAsBytesSync(), orderedEquals(betaBefore));
    expect(gamma.readAsBytesSync(), orderedEquals(gammaBefore));
  });

  test('successor force.updated-by exemption never applies to target', () {
    final (:alpha, :beta, :gamma) = _writeChainedBacklog(register);
    final alphaBefore = alpha.readAsBytesSync();
    final betaBefore = beta.readAsBytesSync();
    final gammaBefore = gamma.readAsBytesSync();

    expect(
      () => service.vacate(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'alpha',
        successor: 'beta',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          'candidate register is not clean: '
              'docs/decisions/2026-01-01-alpha.md [force.updated-by]',
        ),
      ),
    );
    expect(alpha.readAsBytesSync(), orderedEquals(alphaBefore));
    expect(beta.readAsBytesSync(), orderedEquals(betaBefore));
    expect(gamma.readAsBytesSync(), orderedEquals(gammaBefore));
  });

  test('lint keeps reporting unrelated diagnostics after mutation', () {
    _writeEntry(
      register,
      day: 1,
      slug: 'base-rule',
      updatedBy: const ['amendment'],
    );
    _writeEntry(
      register,
      day: 2,
      slug: 'amendment',
      updates: const ['base-rule'],
    );
    _writeEntry(
      register,
      day: 3,
      slug: 'unrelated-rule',
      surface: 'missing/**',
    );
    _writeEntry(
      register,
      day: 4,
      slug: 'unrelated-amendment',
      surface: 'missing/**',
      updates: const ['unrelated-rule'],
    );
    final before = utf8.encode(
      jsonEncode(
        linter
            .lint(registerPath: register.path, repoRoot: sandbox.path)
            .diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(),
      ),
    );

    service.update(
      registerPath: register.path,
      repoRoot: sandbox.path,
      target: 'base-rule',
      successor: 'amendment',
    );

    final after = utf8.encode(
      jsonEncode(
        linter
            .lint(registerPath: register.path, repoRoot: sandbox.path)
            .diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(),
      ),
    );
    expect(after, orderedEquals(before));
  });

  test(
    'update command records a local edge in a roster-wide register end to end',
    () async {
      final target = _writeEntry(
        register,
        day: 1,
        slug: 'base-rule',
        surface: 'roster:CLAUDE.md',
      );
      final successor = _writeEntry(
        register,
        day: 2,
        slug: 'amendment',
        surface: 'roster:CLAUDE.md',
        updates: const ['base-rule'],
      );
      final output = StringBuffer();
      final error = StringBuffer();
      final runner = CommandRunner<int>('station', 'fixture')
        ..addCommand(DecisionsCommand(output: output, error: error));

      final code = await runner.run(<String>[
        'decisions',
        'update',
        'base-rule',
        '--by',
        'amendment',
        '--register',
        register.path,
        '--repo-root',
        sandbox.path,
      ]);

      expect(code, 0);
      expect(output.toString(), 'update base-rule: clean\n');
      expect(error.toString(), isEmpty);
      expect(parseEntry(successor.path).updates, orderedEquals(['base-rule']));
      expect(
        parseEntry(target.path).cachedUpdatedBy,
        orderedEquals(['amendment']),
      );
    },
  );

  test('vacate preserves update cache and leaves lint clean', () {
    final target = _writeEntry(
      register,
      day: 1,
      slug: 'withdrawn-rule',
      updatedBy: const ['prior-amendment'],
    );
    _writeEntry(
      register,
      day: 2,
      slug: 'prior-amendment',
      updates: const ['withdrawn-rule'],
    );
    _writeEntry(
      register,
      day: 3,
      slug: 'no-rule-governs',
      body: 'No rule governs the withdrawn surface.',
    );
    final bodyBefore = _bodyBytes(target);
    final authoredBefore = _authored(parseEntry(target.path));
    _expectClean(linter, register);

    service.vacate(
      registerPath: register.path,
      repoRoot: '.',
      target: 'withdrawn-rule',
      successor: 'no-rule-governs',
    );

    final changed = parseEntry(target.path);
    expect(changed.status, 'deprecated');
    expect(changed.cachedObsoletedBy, isNull);
    expect(changed.cachedUpdatedBy, ['prior-amendment']);
    expect(_bodyBytes(target), orderedEquals(bodyBefore));
    expect(_authored(changed), authoredBefore);
    _expectClean(linter, register);
  });

  test(
    'vacate rejects absent none and unresolved successors without writing',
    () async {
      final target = _writeEntry(register, day: 1, slug: 'target');
      final before = target.readAsBytesSync();

      final invocations = <List<String>>[
        [
          'decisions',
          'vacate',
          'target',
          '--register',
          register.path,
          '--repo-root',
          '.',
        ],
        [
          'decisions',
          'vacate',
          'target',
          '--successor',
          'none',
          '--register',
          register.path,
          '--repo-root',
          '.',
        ],
        [
          'decisions',
          'vacate',
          'target',
          '--successor',
          'missing',
          '--register',
          register.path,
          '--repo-root',
          '.',
        ],
      ];
      for (final invocation in invocations) {
        final output = StringBuffer();
        final error = StringBuffer();
        final runner = CommandRunner<int>('station', 'fixture')
          ..addCommand(DecisionsCommand(output: output, error: error));
        expect(await runner.run(invocation), 1);
        expect(target.readAsBytesSync(), orderedEquals(before));
        expect(output.toString(), isEmpty);
        expect(error.toString(), startsWith('error: '));
      }
    },
  );

  test('authored relations precede force mutation as a separate act', () {
    final target = _writeEntry(register, day: 1, slug: 'target');
    _writeEntry(register, day: 2, slug: 'unrelated-successor');
    final before = target.readAsBytesSync();

    expect(parseEntry(target.path).status, 'accepted');
    expect(
      () => service.obsolete(
        registerPath: register.path,
        repoRoot: '.',
        target: 'target',
        successor: 'unrelated-successor',
      ),
      throwsA(isA<DecisionMutationException>()),
    );
    expect(
      () => service.update(
        registerPath: register.path,
        repoRoot: '.',
        target: 'target',
        successor: 'unrelated-successor',
      ),
      throwsA(isA<DecisionMutationException>()),
    );
    expect(target.readAsBytesSync(), orderedEquals(before));
  });

  group('--max-slug-length', () {
    final longSlug = '${'a' * 59}-${'b' * 60}';
    late Directory longSandbox;
    late String root;
    late String reg;
    late File target;
    late StringBuffer output;
    late StringBuffer error;

    setUp(() {
      longSandbox = Directory.systemTemp.createTempSync('decisions-long-');
      root = p.join(longSandbox.path, 'alpha');
      reg = p.join(root, 'docs', 'decisions');
      File(p.join(root, 'README.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# fixture\n');
      target = _writeLongEntry(reg, day: 1, slug: longSlug);
      output = StringBuffer();
      error = StringBuffer();
    });

    tearDown(() {
      if (longSandbox.existsSync()) longSandbox.deleteSync(recursive: true);
    });

    Future<int> run(List<String> args) => DecisionsCommandRunner(
      output: output,
      error: error,
      registerPaths: () => [reg],
    ).run(args);

    List<String> force(String verb, String option, String successor) => [
      verb,
      longSlug,
      '--$option',
      successor,
      '--register',
      reg,
      '--repo-root',
      root,
    ];

    test('update writes the long target cache under the flag, and refuses '
        'without it', () async {
      _writeLongEntry(
        reg,
        day: 2,
        slug: 'amends-long-rule',
        updates: [longSlug],
      );
      final before = target.readAsBytesSync();

      expect(await run(force('update', 'by', 'amends-long-rule')), 1);
      expect(error.toString(), contains('invalid `slug`'));
      expect(output.toString(), isEmpty);
      expect(target.readAsBytesSync(), orderedEquals(before));

      error.clear();
      expect(
        await run([
          ...force('update', 'by', 'amends-long-rule'),
          '--max-slug-length',
          '160',
        ]),
        0,
      );
      expect(error.toString(), isEmpty);
      expect(output.toString(), 'update $longSlug: clean\n');
      expect(parseEntry(target.path, maxSlugLength: 160).cachedUpdatedBy, [
        'amends-long-rule',
      ]);
    });

    test('obsolete writes the long target cache under the flag', () async {
      _writeLongEntry(
        reg,
        day: 2,
        slug: 'replaces-long-rule',
        obsoletes: [longSlug],
      );
      final before = target.readAsBytesSync();

      expect(await run(force('obsolete', 'by', 'replaces-long-rule')), 1);
      expect(error.toString(), contains('invalid `slug`'));
      expect(target.readAsBytesSync(), orderedEquals(before));

      expect(
        await run([
          ...force('obsolete', 'by', 'replaces-long-rule'),
          '--max-slug-length',
          '160',
        ]),
        0,
      );
      expect(
        parseEntry(target.path, maxSlugLength: 160).status,
        'superseded by replaces-long-rule',
      );
    });

    test('vacate writes the long target cache under the flag', () async {
      _writeLongEntry(reg, day: 2, slug: 'no-rule-governs');
      final before = target.readAsBytesSync();

      expect(await run(force('vacate', 'successor', 'no-rule-governs')), 1);
      expect(error.toString(), contains('invalid `slug`'));
      expect(target.readAsBytesSync(), orderedEquals(before));

      expect(
        await run([
          ...force('vacate', 'successor', 'no-rule-governs'),
          '--max-slug-length',
          '160',
        ]),
        0,
      );
      expect(parseEntry(target.path, maxSlugLength: 160).status, 'deprecated');
    });

    test('resurface writes the long entry under the flag, and refuses '
        'without it', () async {
      File(p.join(root, 'docs', 'x.md')).writeAsStringSync('# x\n');
      final before = target.readAsBytesSync();
      final args = [
        'resurface',
        '--from',
        'README.md',
        '--to',
        'docs/**',
        '--register',
        reg,
        '--repo-root',
        root,
      ];

      expect(await run(args), 1);
      expect(error.toString(), contains('invalid `slug`'));
      expect(output.toString(), isEmpty);
      expect(target.readAsBytesSync(), orderedEquals(before));

      error.clear();
      expect(await run([...args, '--max-slug-length', '160']), 0);
      expect(error.toString(), isEmpty);
      expect(output.toString(), '$longSlug\n');
      expect(parseEntry(target.path, maxSlugLength: 160).surfaces, ['docs/**']);
    });

    test('a --roster sibling is read under the flag', () async {
      final base = _writeLongEntry(reg, day: 2, slug: 'base-rule');
      final longReg = p.join(
        longSandbox.path,
        'long_repo',
        'docs',
        'decisions',
      );
      File(p.join(longSandbox.path, 'long_repo', 'README.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('# fixture\n');
      _writeLongEntry(
        longReg,
        day: 3,
        slug: longSlug,
        updates: ['alpha#base-rule'],
      );
      final before = base.readAsBytesSync();
      final args = [
        'update',
        'base-rule',
        '--by',
        'long_repo#$longSlug',
        '--register',
        reg,
        '--repo-root',
        root,
        '--roster',
        longReg,
      ];

      expect(await run(args), 1);
      expect(base.readAsBytesSync(), orderedEquals(before));

      error.clear();
      expect(await run([...args, '--max-slug-length', '160']), 0);
      expect(error.toString(), isEmpty);
      expect(parseEntry(base.path, maxSlugLength: 160).cachedUpdatedBy, [
        'long_repo#$longSlug',
      ]);
    });
  });
}

/// Writes an accepted entry governing `README.md`, quoting every reference.
File _writeLongEntry(
  String register, {
  required int day,
  required String slug,
  List<String> obsoletes = const [],
  List<String> updates = const [],
}) {
  String list(List<String> values) =>
      '[${values.map((value) => '"$value"').join(', ')}]';
  final date = '2026-11-${day.toString().padLeft(2, '0')}';
  return File(p.join(register, '$date-$slug.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
---
status: accepted
date: $date
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: "$slug"
  surfaces:
    - "README.md"
  obsoletes: ${list(obsoletes)}
  updates: ${list(updates)}
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $slug

A fixture decision body.
''');
}

({File alpha, File beta, File gamma}) _writeChainedBacklog(
  Directory register, {
  String betaSurface = 'lib/**',
}) {
  final alpha = _writeEntry(
    register,
    day: 1,
    slug: 'alpha',
    updates: const ['gamma'],
  );
  final beta = _writeEntry(
    register,
    day: 2,
    slug: 'beta',
    updates: const ['alpha'],
    surface: betaSurface,
  );
  final gamma = _writeEntry(
    register,
    day: 3,
    slug: 'gamma',
    updates: const ['beta'],
  );
  return (alpha: alpha, beta: beta, gamma: gamma);
}

File _writeEntry(
  Directory register, {
  required int day,
  required String slug,
  String status = 'accepted',
  List<String> obsoletes = const [],
  List<String> updates = const [],
  String? obsoletedBy,
  List<String> updatedBy = const [],
  String surface = 'lib/**',
  List<String>? surfaces,
  String body = 'A fixture decision body.',
}) {
  final date = '2026-01-${day.toString().padLeft(2, '0')}';
  final file = File(p.join(register.path, '$date-$slug.md'));
  final surfacesYaml = surfaces == null
      ? '["$surface"]'
      : surfaces.map((value) => '\n    - "$value"').join();
  file.writeAsStringSync('''
---
status: $status
date: $date
decision-makers: [fixture]
register:
  spec: 1
  slug: $slug
  surfaces: $surfacesYaml
  obsoletes: ${_yamlList(obsoletes)}
  updates: ${_yamlList(updates)}
  obsoleted-by: ${obsoletedBy ?? 'null'}
  updated-by: ${_yamlList(updatedBy)}
  bead: null
  legacy-id: null
---

# $slug

$body
''');
  return file;
}

String _yamlList(List<String> values) => '[${values.join(', ')}]';

List<int> _bodyBytes(File file) {
  final source = file.readAsStringSync();
  final match = RegExp(
    r'^---\r?\n.*?\r?\n---\r?\n',
    dotAll: true,
  ).firstMatch(source)!;
  return utf8.encode(source.substring(match.end));
}

Map<String, Object?> _authored(DecisionEntry entry) => {
  'date': entry.date,
  'spec': entry.spec,
  'slug': entry.slug,
  'surfaces': entry.surfaces,
  'obsoletes': entry.obsoletes,
  'updates': entry.updates,
  'bead': entry.bead,
  'legacyId': entry.legacyId,
  'decisionMakers': entry.decisionMakers,
};

/// `alpha` carries `lib/**` in a flow list, `beta` carries `docs/**` and
/// `lib/**` in a block list, and `gamma` carries only `docs/**`.
({File alpha, File beta, File gamma}) _writeResurfaceFixture(
  Directory register,
) => (
  alpha: _writeEntry(register, day: 1, slug: 'alpha'),
  beta: _writeEntry(
    register,
    day: 2,
    slug: 'beta',
    surfaces: const ['docs/**', 'lib/**'],
  ),
  gamma: _writeEntry(register, day: 3, slug: 'gamma', surface: 'docs/**'),
);

/// Every file in [register], by name, with its bytes.
Map<String, String> _registerBytes(Directory register) => {
  for (final file in register.listSync().whereType<File>())
    p.basename(file.path): base64.encode(file.readAsBytesSync()),
};

/// A linter that reports `fixture.rule` on alpha in any register but [live].
final class _CandidateOnlyLinter implements DecisionLinter {
  _CandidateOnlyLinter(this.live);

  final String live;

  @override
  DecisionLintResult lint({
    required String registerPath,
    required String repoRoot,
  }) => DecisionLintResult(
    register: registerPath,
    diagnostics: [
      if (!p.equals(registerPath, live))
        DecisionLintDiagnostic(
          ruleId: 'fixture.rule',
          file: p.normalize(
            p.relative(
              p.join(registerPath, '2026-01-01-alpha.md'),
              from: p.absolute(repoRoot),
            ),
          ),
          message: 'reported on the candidate only',
        ),
    ],
  );
}

void _expectClean(DecisionLinter linter, Directory register) {
  final result = linter.lint(registerPath: register.path, repoRoot: '.');
  expect(result.isClean, isTrue, reason: '${result.toJson()}');
}
