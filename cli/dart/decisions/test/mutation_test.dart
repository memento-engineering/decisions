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
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
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
        final runner = CommandRunner<int>('station', 'fixture')
          ..addCommand(DecisionsCommand(output: StringBuffer()));
        expect(await runner.run(invocation), 1);
        expect(target.readAsBytesSync(), orderedEquals(before));
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
  String body = 'A fixture decision body.',
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
  surfaces: ["lib/**"]
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

void _expectClean(DecisionLinter linter, Directory register) {
  final result = linter.lint(registerPath: register.path, repoRoot: '.');
  expect(result.isClean, isTrue, reason: '${result.toJson()}');
}
