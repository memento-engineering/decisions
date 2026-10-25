import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A roster assembled in memory, with no register directory behind it.
final class FakeDecisionRoster implements DecisionRoster {
  FakeDecisionRoster(Iterable<DecisionRegisterSnapshot> registers)
    : registers = List<DecisionRegisterSnapshot>.unmodifiable(registers);

  @override
  final List<DecisionRegisterSnapshot> registers;

  @override
  DecisionRegisterSnapshot? findRegister(String originRegister) {
    for (final register in registers) {
      if (register.originRegister == originRegister) return register;
    }
    return null;
  }
}

const _body = '''
## Context and Problem Statement

Something forced a call.

## Decision Outcome

The call.
''';

void main() {
  late Directory sandbox;
  late String repoRoot;
  late String registerPath;
  final service = DecisionRecordService(clock: () => DateTime(2026, 10, 24));
  const linter = DecisionLintService();

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decisions-record-test-');
    repoRoot = p.join(sandbox.path, 'alpha');
    registerPath = p.join(repoRoot, 'docs', 'decisions');
    File(p.join(repoRoot, 'lib', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  DecisionDraft draft({
    String slug = 'new-rule',
    String title = 'A new rule',
    List<String> surfaces = const ['lib/fixture.dart'],
    List<String> decisionMakers = const ['nico'],
    List<String> obsoletes = const [],
    List<String> updates = const [],
    String? bead,
    String? date,
    String body = _body,
  }) => DecisionDraft(
    slug: slug,
    title: title,
    surfaces: surfaces,
    decisionMakers: decisionMakers,
    obsoletes: obsoletes,
    updates: updates,
    bead: bead,
    date: date,
    body: body,
  );

  DecisionRecordResult record(
    DecisionDraft value, {
    DecisionRecorder? recorder,
  }) => (recorder ?? service).record(
    registerPath: registerPath,
    repoRoot: repoRoot,
    draft: value,
  );

  void expectRefused(
    DecisionDraft value,
    Pattern message, {
    DecisionRecorder? recorder,
  }) {
    final before = _snapshot(registerPath);
    expect(
      () => record(value, recorder: recorder),
      throwsA(
        isA<DecisionRecordException>().having(
          (error) => error.message,
          'message',
          contains(message),
        ),
      ),
    );
    expect(_snapshot(registerPath), before, reason: 'nothing is written');
  }

  test('writes birth values, creates the register, and lints clean', () {
    final result = record(draft(bead: 'dec-abc'));

    expect(result.path, p.join(registerPath, '2026-10-24-new-rule.md'));
    expect(result.citation, 'alpha#new-rule');
    expect(result.nextSteps, isEmpty);
    final entry = parseEntry(result.path);
    expect(entry.status, 'accepted');
    expect(entry.date, '2026-10-24');
    expect(entry.spec, 1);
    expect(entry.slug, 'new-rule');
    expect(entry.surfaces, ['lib/fixture.dart']);
    expect(entry.decisionMakers, ['nico']);
    expect(entry.obsoletes, isEmpty);
    expect(entry.updates, isEmpty);
    expect(entry.cachedObsoletedBy, isNull);
    expect(entry.cachedUpdatedBy, isEmpty);
    expect(entry.bead, 'dec-abc');
    expect(entry.legacyId, isNull);
    expect(entry.body, startsWith('# A new rule\n\n## Context and Problem'));
    expect(File(result.path).readAsStringSync(), endsWith('The call.\n'));
    expect(
      linter.lint(registerPath: registerPath, repoRoot: repoRoot).isClean,
      isTrue,
    );
  });

  test('an explicit date wins over the clock', () {
    final result = record(draft(date: '2025-01-31'));

    expect(p.basename(result.path), '2025-01-31-new-rule.md');
  });

  test('free text round-trips through YAML quoting', () {
    const awkward = [
      'Nico "N" Spencer: lead',
      'null',
      '# not a comment',
      'yes',
    ];
    final result = record(
      DecisionDraft(
        slug: 'quoted',
        title: 'Quoted',
        surfaces: const ['lib/*.dart'],
        decisionMakers: awkward,
        consulted: const ['a: b'],
        informed: const ["it's"],
        body: _body,
      ),
    );

    final entry = parseEntry(result.path);
    expect(entry.decisionMakers, awkward);
    expect(entry.surfaces, ['lib/*.dart']);
  });

  group('refuses, writing nothing,', () {
    for (final slug in [
      'Upper',
      'trailing-',
      'double--dash',
      'under_score',
      'a' * 81,
    ]) {
      test('the malformed slug "${slug.length > 20 ? 'a*81' : slug}"', () {
        expectRefused(draft(slug: slug), 'invalid slug');
      });
    }

    test('a slug already recorded on another date', () {
      final first = record(draft(date: '2026-01-01'));

      expectRefused(draft(), 'already recorded in ${first.path}');
    });

    test('a target file that already exists', () {
      final path = p.join(registerPath, '2026-10-24-new-rule.md');
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync('not an entry\n');

      expectRefused(draft(), 'already recorded in $path');
    });

    test('a body carrying its own H1', () {
      expectRefused(draft(body: '# Title\n\n$_body'), 'must not carry an H1');
    });

    test('a body missing a required section', () {
      expectRefused(
        draft(body: '## Context and Problem Statement\n\nWhy.\n'),
        '"## Decision Outcome"',
      );
    });

    test('a required section at the wrong level', () {
      expectRefused(
        draft(
          body: _body.replaceFirst(
            '## Decision Outcome',
            '### Decision Outcome',
          ),
        ),
        '"## Decision Outcome"',
      );
    });

    test('a surface that matches nothing', () {
      expectRefused(
        draft(surfaces: const ['lib/missing/**']),
        '[surface.unmatched]',
      );
    });

    test('an edge to a local slug that does not exist', () {
      expectRefused(
        draft(updates: const ['no-such-rule']),
        '[edge.dangling-local]',
      );
    });

    test('a qualified edge naming its own register', () {
      _writeEntry(registerPath, slug: 'base-rule');

      expectRefused(
        draft(updates: const ['alpha#base-rule']),
        'pass the bare slug "base-rule"',
      );
    });

    test('a qualified edge the roster carries but cannot resolve', () {
      final roster = FakeDecisionRoster([
        DecisionRegisterSnapshot(
          originRegister: 'bravo',
          originPath: 'bravo/docs/decisions',
          entries: const [],
        ),
      ]);

      expectRefused(
        draft(obsoletes: const ['bravo#gone']),
        '[edge.dangling-cross-register]',
        recorder: DecisionRecordService(
          clock: () => DateTime(2026, 10, 24),
          roster: roster,
        ),
      );
    });

    test('an invalid date', () {
      expectRefused(draft(date: '2026-02-30'), 'invalid date');
    });

    test('a multi-line title', () {
      expectRefused(draft(title: 'one\ntwo'), 'one line');
    });
  });

  test('a heading inside a fenced block is not a heading', () {
    final result = record(draft(body: '$_body\n```md\n# example\n```\n'));

    expect(File(result.path).readAsStringSync(), contains('# example'));
  });

  test('a roster-wide surface is accepted unresolved', () {
    final result = record(draft(surfaces: const ['roster:CLAUDE.md']));

    expect(parseEntry(result.path).surfaces, ['roster:CLAUDE.md']);
  });

  test('dirt elsewhere in the register does not block the write', () {
    _writeEntry(registerPath, slug: 'dirty', surface: 'lib/missing/**');

    expect(File(record(draft()).path).existsSync(), isTrue);
  });

  test('a local edge names the force verb that completes it', () {
    _writeEntry(registerPath, slug: 'base-rule');
    _writeEntry(registerPath, slug: 'old-rule', day: 2);

    final result = record(
      draft(obsoletes: const ['old-rule'], updates: const ['base-rule']),
    );

    expect(result.nextSteps.map((step) => step.command), [
      'decisions obsolete old-rule --by new-rule',
      'decisions update base-rule --by new-rule',
    ]);

    const mutations = DecisionMutationService();
    for (final step in result.nextSteps) {
      final run = switch (step.kind) {
        DecisionEdgeKind.obsoletes => mutations.obsolete,
        DecisionEdgeKind.updates => mutations.update,
      };
      run(
        registerPath: registerPath,
        repoRoot: repoRoot,
        target: step.target,
        successor: step.successor,
      );
    }
    expect(
      linter.lint(registerPath: registerPath, repoRoot: repoRoot).isClean,
      isTrue,
    );
  });

  test('a cross-register edge names the register and qualified successor', () {
    final result = record(draft(updates: const ['bravo#their-rule']));

    final step = result.nextSteps.single;
    expect(step.register, 'bravo');
    expect(step.target, 'their-rule');
    expect(step.successor, 'alpha#new-rule');
    expect(
      step.command,
      'decisions update their-rule --by alpha#new-rule '
      '(run in register bravo)',
    );
  });
}

/// Every file under [directory] with its contents, or empty when absent.
Map<String, String> _snapshot(String directory) {
  final root = Directory(directory);
  if (!root.existsSync()) return const {};
  return {
    for (final file in root.listSync(recursive: true).whereType<File>())
      file.path: file.readAsStringSync(),
  };
}

void _writeEntry(
  String registerPath, {
  required String slug,
  int day = 1,
  String surface = 'lib/fixture.dart',
}) {
  File(p.join(registerPath, '2026-01-0$day-$slug.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
---
status: accepted
date: 2026-01-0$day
decision-makers: [nico]
consulted: []
informed: []
register:
  spec: 1
  slug: $slug
  surfaces:
    - "$surface"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $slug

## Context and Problem Statement

Fixture.

## Decision Outcome

Fixture.
''');
}
