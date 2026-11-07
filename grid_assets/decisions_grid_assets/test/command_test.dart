import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions_grid_assets/decisions_grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _sourceRoot =
    '../../cli/dart/decisions/test/fixtures/index_registers/source_repo';
const String _otherRoot =
    '../../cli/dart/decisions/test/fixtures/index_registers/other_repo';
const String _orgRoot =
    '../../cli/dart/decisions/test/fixtures/search_registers/'
    'memento-engineering';

final class FakeResidentStationContext {
  FakeResidentStationContext(this.roots);

  List<String> roots;
  int reads = 0;

  Iterable<String> mountedSubstationRoots() {
    reads++;
    return List<String>.unmodifiable(roots);
  }
}

void main() {
  test('station composition exposes search and runtime roster index', () async {
    final resident = FakeResidentStationContext(['ignored-at-construction']);
    final output = StringBuffer();
    final command = buildDecisionsCommand(
      mountedSubstationRoots: resident.mountedSubstationRoots,
      output: output,
    );
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(command);

    expect(resident.reads, 0);
    expect(runner.commands['decisions'], same(command));
    expect(command.subcommands.keys, containsAll(['lint', 'index', 'search']));

    resident.roots = [_sourceRoot, _otherRoot, 'missing-substation'];
    expect(await runner.run(['decisions', 'index']), 0);
    expect(resident.reads, 1);

    final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
    final decisions = (decoded['decisions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(decisions, hasLength(2));
    expect(
      decisions.map((decision) => decision['originRegister']),
      unorderedEquals(['source_repo', 'other_repo']),
    );
  });

  test(
    'roster search finds org-928 and org-6ku in a sibling register',
    () async {
      final resident = FakeResidentStationContext(<String>[
        'ignored-at-construction',
      ]);
      final output = StringBuffer();
      final errors = StringBuffer();
      final command = buildDecisionsCommand(
        mountedSubstationRoots: resident.mountedSubstationRoots,
        output: output,
        error: errors,
      );
      final runner = CommandRunner<int>('station', 'fixture')
        ..addCommand(command);

      expect(resident.reads, 0);
      resident.roots = <String>[_sourceRoot, _orgRoot];
      expect(
        await runner.run(<String>[
          'decisions',
          'search',
          '--json',
          'publish',
          'prerelease',
        ]),
        0,
      );
      expect(resident.reads, 1);
      expect(errors.toString(), isEmpty);

      final hits = const LineSplitter()
          .convert(output.toString())
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList(growable: false);
      expect(hits, hasLength(2));
      expect(
        hits.map((hit) => hit['register']),
        everyElement('memento-engineering'),
      );
      expect(hits.map((hit) => hit['slug']), <String>[
        'agents-publish-prereleases-humans-promote-to-stable',
        'prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only',
      ]);
    },
  );

  test('empty resident roster is refused loudly', () async {
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        buildDecisionsCommand(
          mountedSubstationRoots: () => const ['missing-substation'],
          registerExists: (_) => false,
          output: StringBuffer(),
        ),
      );

    await expectLater(
      runner.run(['decisions', 'index']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
  });

  test('empty roster search is refused loudly', () async {
    final output = StringBuffer();
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        buildDecisionsCommand(
          mountedSubstationRoots: () => const <String>['missing-substation'],
          registerExists: (_) => false,
          output: output,
          error: StringBuffer(),
        ),
      );

    await expectLater(
      runner.run(<String>['decisions', 'search', 'precedent']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
    expect(output.toString(), isEmpty);
  });

  group("a station composes each register's slug limit", () {
    final longSlug = '${'a' * 59}-${'b' * 60}';
    late Directory sandbox;
    late String longRoot;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('decisions-grid-limit-');
      longRoot = p.join(sandbox.path, 'long_repo');
      File(p.join(longRoot, 'docs', 'decisions', '2026-11-05-$longSlug.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
---
status: accepted
date: 2026-11-05
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: "$longSlug"
  surfaces:
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# A long rule

Fixture.
''');
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    Future<Map<String, dynamic>> index({DecisionSlugLimits? slugLimits}) async {
      final output = StringBuffer();
      final command = slugLimits == null
          ? buildDecisionsCommand(
              mountedSubstationRoots: () => [longRoot],
              output: output,
            )
          : buildDecisionsCommand(
              mountedSubstationRoots: () => [longRoot],
              slugLimits: slugLimits,
              output: output,
            );
      final runner = CommandRunner<int>('station', 'fixture')
        ..addCommand(command);
      expect(await runner.run(['decisions', 'index']), 0);
      return jsonDecode(output.toString()) as Map<String, dynamic>;
    }

    test('the composed limit reads the long entry', () async {
      final decoded = await index(
        slugLimits: const DecisionSlugLimits(byRegister: {'long_repo': 160}),
      );
      final decisions = (decoded['decisions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(decisions, hasLength(1));
      expect(decisions.single['originRegister'], 'long_repo');
      expect(decisions.single['slug'], longSlug);
      expect(decoded['diagnostics'], isEmpty);
    });

    test('without one, the default reports the slug', () async {
      expect(defaultMaxSlugLength, 80);
      final decoded = await index();
      expect(decoded['decisions'], isEmpty);
      final diagnostics = (decoded['diagnostics'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single['message'], 'invalid `slug`');
    });
  });

  test('declares spec-1 read range and no writes', () {
    expect(decisionsGridAssetsReadSpecMinimum, 1);
    expect(decisionsGridAssetsReadSpecMaximum, 1);
    expect(decisionsGridAssetsWrittenDecisionSpecs, isEmpty);
  });
}
