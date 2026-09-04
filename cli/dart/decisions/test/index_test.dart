import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:test/test.dart';

const _sourceRegister =
    'test/fixtures/index_registers/source_repo/docs/decisions';
const _otherRegister =
    'test/fixtures/index_registers/other_repo/docs/decisions';
const _futureRegister =
    'test/fixtures/index_registers/future_repo/docs/decisions';
const _malformedRegister =
    'test/fixtures/index_registers/malformed_repo/docs/decisions';
const _liveSlug =
    'intake-argv-rides-bdcliservice-with-a-per-key-metadata-channel';
const _malformedEntry = '$_malformedRegister/2026-01-02-$_liveSlug.md';

void main() {
  test('resolves a cross-register legacy reference in the union', () {
    final index = DecisionIndex.fromRegisterPaths([
      _sourceRegister,
      _otherRegister,
    ]);
    final source = _decision(index, 'source_repo', 'watcher-policy');

    expect(index.toJson()['spec'], decisionIndexOutputSpec);
    expect(source.toJson(), {
      'originRegister': 'source_repo',
      'originPath': _sourceRegister,
      'slug': 'watcher-policy',
      'status': 'accepted',
      'surfaces': ['lib/watcher/**'],
      'edges': [
        {
          'kind': 'updates',
          'reference': 'other_repo#A50',
          'resolution': 'resolved',
          'targetRegister': 'other_repo',
          'targetSlug': 'no-file-watching',
        },
      ],
    });
  });

  test('reports an absent cross-register target as dangling', () {
    final index = DecisionIndex.fromRegisterPaths([_sourceRegister]);
    final edge = _decision(index, 'source_repo', 'watcher-policy').edges.single;

    expect(edge.resolution, DecisionIndexEdgeResolution.dangling);
    expect(edge.targetRegister, isNull);
    expect(edge.targetSlug, isNull);
    expect(edge.toJson(), {
      'kind': 'updates',
      'reference': 'other_repo#A50',
      'resolution': 'dangling',
    });
  });

  test('filters by a roster-qualified governed surface path', () {
    final filtered = DecisionIndex.fromRegisterPaths([
      _sourceRegister,
      _otherRegister,
    ]).governing('source_repo/lib/watcher/service.dart');

    expect(
      filtered.decisions.map(
        (decision) => '${decision.originRegister}#${decision.slug}',
      ),
      ['source_repo#watcher-policy'],
    );
  });

  test('does not mutate any register file', () {
    final before = _snapshot([_sourceRegister, _otherRegister]);
    final index = DecisionIndex.fromRegisterPaths([
      _sourceRegister,
      _otherRegister,
    ]);

    index.toJson();
    index.governing('source_repo/lib/watcher/service.dart').toJson();

    expect(_snapshot([_sourceRegister, _otherRegister]), before);
  });

  test('declares schema versions and refuses a future entry spec', () {
    expect(decisionEntrySpecMinimum, 1);
    expect(decisionEntrySpecMaximum, 1);
    expect(decisionIndexOutputSpec, 2);
    expect(
      DecisionIndex.fromRegisterPaths([_sourceRegister]).decisions,
      isNotEmpty,
    );
    expect(
      () => DecisionIndex.fromRegisterPaths([_futureRegister]),
      throwsA(
        isA<DecisionIndexException>().having(
          (error) => error.message,
          'message',
          allOf(contains('spec 2'), contains('supported range is 1 through 1')),
        ),
      ),
    );
  });

  test('keeps a clean roster decision when a sibling entry is malformed', () {
    final union = DecisionIndex.fromRegisterPaths([
      _sourceRegister,
      _malformedRegister,
    ]);

    expect(
      union.decisions.map(
        (decision) => '${decision.originRegister}#${decision.slug}',
      ),
      containsAll([
        'source_repo#watcher-policy',
        'malformed_repo#healthy-rule',
      ]),
    );
    final filtered = union.governing('source_repo/lib/watcher/service.dart');
    expect(
      filtered.decisions.map(
        (decision) => '${decision.originRegister}#${decision.slug}',
      ),
      ['source_repo#watcher-policy'],
    );
    expect(filtered.diagnostics.single.file, _malformedEntry);
  });

  test('index and lint share the malformed-entry reason', () {
    final indexed = DecisionIndex.fromRegisterPaths([_malformedRegister]);
    final linted = const DecisionLintService().lint(
      registerPath: _malformedRegister,
      repoRoot: '.',
    );
    final lintDiagnostic = linted.diagnostics.singleWhere(
      (diagnostic) => diagnostic.file == _malformedEntry,
    );

    expect(indexed.diagnostics.single.toJson(), lintDiagnostic.toJson());
    expect(indexed.diagnostics.single.ruleId, DecisionLintRules.entrySchema);
    expect(indexed.diagnostics.single.message, 'invalid `slug`');
  });

  test('pins the live 62-character slug and keeps its healthy sibling', () {
    expect(_liveSlug.length, 62);
    final index = DecisionIndex.fromRegisterPaths([_malformedRegister]);

    expect(index.decisions.single.slug, 'healthy-rule');
    expect(index.diagnostics.single.file, _malformedEntry);
  });
}

IndexedDecision _decision(
  DecisionIndex index,
  String originRegister,
  String slug,
) => index.decisions.singleWhere(
  (decision) =>
      decision.originRegister == originRegister && decision.slug == slug,
);

Map<String, String> _snapshot(Iterable<String> directories) {
  final files = [
    for (final directory in directories)
      ...Directory(directory).listSync().whereType<File>(),
  ]..sort((left, right) => left.path.compareTo(right.path));
  return {for (final file in files) file.path: file.readAsStringSync()};
}
