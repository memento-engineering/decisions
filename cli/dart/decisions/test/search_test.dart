import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _orgRegister =
    'test/fixtures/search_registers/memento-engineering/docs/decisions';
const _sourceRegister =
    'test/fixtures/index_registers/source_repo/docs/decisions';

void main() {
  const service = DecisionSearchService();

  test('title slug and body each match under OR-token lexical semantics', () {
    final title = service.search(
      query: 'InItIaTe',
      registerPaths: const <String>[_orgRegister],
    );
    final slug = service.search(
      query: 'rungs-are',
      registerPaths: const <String>[_orgRegister],
    );
    final body = service.search(
      query: 'irreversibility',
      registerPaths: const <String>[_orgRegister],
    );
    final anyTerm = service.search(
      query: 'stable rungs-are',
      registerPaths: const <String>[_orgRegister],
    );

    expect(title.hits.single.field, 'title');
    expect(
      title.hits.single.slug,
      'agents-publish-prereleases-humans-promote-to-stable',
    );
    expect(slug.hits.single.field, 'slug');
    expect(
      slug.hits.single.slug,
      'prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only',
    );
    expect(body.hits.single.field, 'body');
    expect(body.hits.single.snippet, contains('irreversibility'));
    expect(anyTerm.hits.map((hit) => hit.slug), <String>[
      'agents-publish-prereleases-humans-promote-to-stable',
      'prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only',
    ]);
  });

  test('orders by register then slug without relevance ranking', () {
    final result = service.search(
      query: 'policy prerelease',
      registerPaths: const <String>[_sourceRegister, _orgRegister],
    );

    expect(result.hits.map((hit) => '${hit.register}#${hit.slug}'), <String>[
      'memento-engineering#'
          'agents-publish-prereleases-humans-promote-to-stable',
      'memento-engineering#'
          'prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only',
      'source_repo#watcher-policy',
    ]);
  });

  test(
    'all front-matter filters intersect and raw status remains distinguishable',
    () {
      final sandbox = Directory.systemTemp.createTempSync('decision-search-');
      try {
        final register = p.join(
          sandbox.path,
          'filter_repo',
          'docs',
          'decisions',
        );
        _writeFilterRegister(register);

        final result = service.search(
          query: 'policy',
          registerPaths: <String>[register],
          filters: const DecisionSearchFilters(
            statuses: <DecisionSearchStatusFilter>[
              DecisionSearchStatusFilter.accepted,
            ],
            dateFrom: '2026-02-02',
            dateThrough: '2026-02-02',
            decisionMakers: <String>['architect', 'nobody'],
            slugs: <String>['everything-rule', 'missing'],
            surfaces: <String>['filter_repo/lib/search.dart'],
            obsoletes: <String>['old-rule'],
            updates: <String>['base-rule'],
            obsoletedBy: <String>['successor-rule'],
            updatedBy: <String>['later-rule'],
          ),
        );

        expect(result.hits.single.slug, 'everything-rule');
        expect(result.hits.single.status, 'accepted');

        DecisionSearchHit byStatus(DecisionSearchStatusFilter status) => service
            .search(
              query: 'policy',
              registerPaths: <String>[register],
              filters: DecisionSearchFilters(
                statuses: <DecisionSearchStatusFilter>[status],
              ),
            )
            .hits
            .single;

        expect(
          byStatus(DecisionSearchStatusFilter.obsoleted).status,
          'superseded by successor-rule',
        );
        expect(
          byStatus(DecisionSearchStatusFilter.vacated).status,
          'deprecated',
        );
        expect(
          byStatus(DecisionSearchStatusFilter.rejected).status,
          'rejected',
        );
      } finally {
        sandbox.deleteSync(recursive: true);
      }
    },
  );

  test('snippets are one line and count both ellipses inside the cap', () {
    final sandbox = Directory.systemTemp.createTempSync('decision-search-');
    try {
      final register = p.join(
        sandbox.path,
        'snippet_repo',
        'docs',
        'decisions',
      );
      Directory(register).createSync(recursive: true);
      final clippedLine =
          '${List<String>.filled(100, 'a').join()}needle'
          '${List<String>.filled(100, 'b').join()}';
      final boundaryLine =
          '${List<String>.filled(70, 'c').join()}marker'
          '${List<String>.filled(84, 'd').join()}';
      _writeEntry(
        register,
        date: '2026-03-01',
        slug: 'clipped-rule',
        body: '# Clipped rule\n\n$clippedLine',
      );
      _writeEntry(
        register,
        date: '2026-03-02',
        slug: 'boundary-rule',
        body: '# Boundary rule\n\n$boundaryLine',
      );

      final clipped = service
          .search(query: 'needle', registerPaths: <String>[register])
          .hits
          .single
          .snippet;
      final boundary = service
          .search(query: 'marker', registerPaths: <String>[register])
          .hits
          .single
          .snippet;

      expect(clipped.length, decisionSearchSnippetCap);
      expect(clipped, startsWith('…'));
      expect(clipped, endsWith('…'));
      expect(clipped, isNot(contains('\n')));
      expect(boundary.length, decisionSearchSnippetCap);
      expect(boundary, boundaryLine);
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('retains tolerant parse diagnostics beside healthy hits', () {
    final result = service.search(
      query: 'healthy',
      registerPaths: const <String>[
        'test/fixtures/index_registers/malformed_repo/docs/decisions',
      ],
    );

    expect(result.hits.single.slug, 'healthy-rule');
    expect(result.diagnostics, hasLength(1));
    expect(result.diagnostics.single.ruleId, DecisionLintRules.entrySchema);
  });

  test('searches a migrated body that has no level-one heading', () {
    final sandbox = Directory.systemTemp.createTempSync('decision-search-');
    try {
      final register = p.join(
        sandbox.path,
        'migrated_repo',
        'docs',
        'decisions',
      );
      Directory(register).createSync(recursive: true);
      _writeEntry(
        register,
        date: '2026-03-03',
        slug: 'migrated-rule',
        body: '## Decision Outcome\n\nLegacy lookup remains available.',
      );

      final result = service.search(
        query: 'legacy lookup',
        registerPaths: <String>[register],
      );

      expect(result.hits.single.field, 'body');
      expect(result.hits.single.slug, 'migrated-rule');
    } finally {
      sandbox.deleteSync(recursive: true);
    }
  });

  test('rejects a blank query instead of returning the whole register', () {
    expect(
      () => service.search(
        query: '  ',
        registerPaths: const <String>[_orgRegister],
      ),
      throwsArgumentError,
    );
  });
}

void _writeFilterRegister(String register) {
  Directory(register).createSync(recursive: true);
  _writeEntry(
    register,
    date: '2026-02-01',
    slug: 'base-rule',
    body: '# Base policy',
  );
  _writeEntry(
    register,
    date: '2026-02-01',
    slug: 'old-rule',
    status: 'superseded by successor-rule',
    obsoletedBy: 'successor-rule',
    body: '# Old policy',
  );
  _writeEntry(
    register,
    date: '2026-02-02',
    slug: 'everything-rule',
    decisionMakers: const <String>['Architect'],
    surfaces: const <String>['lib/**'],
    obsoletes: const <String>['old-rule'],
    updates: const <String>['base-rule'],
    obsoletedBy: 'successor-rule',
    updatedBy: const <String>['later-rule'],
    body: '# Everything policy',
  );
  _writeEntry(
    register,
    date: '2026-02-03',
    slug: 'vacated-rule',
    status: 'deprecated',
    body: '# Vacated policy',
  );
  _writeEntry(
    register,
    date: '2026-02-04',
    slug: 'rejected-rule',
    status: 'rejected',
    body: '# Rejected policy',
  );
}

void _writeEntry(
  String register, {
  required String date,
  required String slug,
  required String body,
  String status = 'accepted',
  List<String> decisionMakers = const <String>['fixture'],
  List<String> surfaces = const <String>['lib/**'],
  List<String> obsoletes = const <String>[],
  List<String> updates = const <String>[],
  String? obsoletedBy,
  List<String> updatedBy = const <String>[],
}) {
  String yamlList(List<String> values) =>
      '[${values.map((value) => '"$value"').join(', ')}]';
  final file = File(p.join(register, '$date-$slug.md'));
  file.writeAsStringSync('''
---
status: $status
date: $date
decision-makers: ${yamlList(decisionMakers)}
register:
  spec: 1
  slug: $slug
  surfaces: ${yamlList(surfaces)}
  obsoletes: ${yamlList(obsoletes)}
  updates: ${yamlList(updates)}
  obsoleted-by: ${obsoletedBy ?? 'null'}
  updated-by: ${yamlList(updatedBy)}
  bead: null
  legacy-id: null
---

$body
''');
}
