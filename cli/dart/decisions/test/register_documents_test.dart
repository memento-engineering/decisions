import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Register documents — `README.md`, the `STYLE.md` style guide — sit beside
/// entries in a register directory and are never read as entries.
void main() {
  group('isDecisionEntryFile', () {
    test('admits dated entries and any other lowercase Markdown', () {
      expect(isDecisionEntryFile('docs/decisions/2026-01-01-a-rule.md'), true);
      expect(isDecisionEntryFile('notes.md'), isTrue);
      expect(isDecisionEntryFile('Readme.md'), isTrue);
    });

    test('rejects all-uppercase register documents', () {
      for (final name in [
        'README.md',
        'STYLE.md',
        'CONTRIBUTING.md',
        'CODE_OF-CONDUCT2.md',
      ]) {
        expect(
          isDecisionEntryFile(p.join('docs', 'decisions', name)),
          isFalse,
          reason: name,
        );
      }
    });

    test('rejects files that are not Markdown', () {
      expect(isDecisionEntryFile('docs/decisions/.gitkeep'), isFalse);
      expect(isDecisionEntryFile('docs/decisions/2026-01-01-a.txt'), isFalse);
      expect(isDecisionEntryFile('docs/decisions/README.MD'), isFalse);
    });
  });

  group('a register holding README.md and STYLE.md', () {
    late Directory sandbox;
    late Directory register;
    late File readme;
    late File style;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('decisions-documents-');
      register = Directory(p.join(sandbox.path, 'docs', 'decisions'))
        ..createSync(recursive: true);
      File(p.join(sandbox.path, 'lib', 'fixture.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('final class Fixture {}\n');
      readme = File(p.join(register.path, 'README.md'))
        ..writeAsStringSync('# Decisions\n\nThis directory is a register.\n');
      style = File(p.join(register.path, 'STYLE.md'))
        ..writeAsStringSync(
          '# Style\n\nTitles are declarative sentences. Write in the present '
          'tense.\n',
        );
      _writeEntry(register, day: 1, slug: 'old-rule');
      _writeEntry(register, day: 2, slug: 'replacement');
    });

    tearDown(() {
      if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
    });

    test('reads only the entries', () {
      final reported = <DecisionParseException>[];
      final entries = readRegister(register.path, onParseError: reported.add);

      expect(entries.map((entry) => entry.slug), ['old-rule', 'replacement']);
      expect(reported, isEmpty);
    });

    test('lints clean', () {
      final result = const DecisionLintService().lint(
        registerPath: register.path,
        repoRoot: sandbox.path,
      );

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
      expect(result.diagnostics, isEmpty);
    });

    test('indexes without them', () {
      final index = DecisionIndex.fromRegisterPaths([register.path]);

      expect(index.decisions.map((decision) => decision.slug), [
        'old-rule',
        'replacement',
      ]);
      expect(index.diagnostics, isEmpty);
    });

    test('still reports a lowercase file that is not a well-formed entry', () {
      File(
        p.join(register.path, 'notes.md'),
      ).writeAsStringSync('# Notes\n\nNot an entry.\n');

      final result = const DecisionLintService().lint(
        registerPath: register.path,
        repoRoot: sandbox.path,
      );

      expect(
        result.diagnostics.map((item) => (item.ruleId, p.basename(item.file))),
        [(DecisionLintRules.entrySchema, 'notes.md')],
      );
    });

    test('a force mutation succeeds and leaves them untouched', () {
      // Authoring the edge is its own act; the mutation then fills the cache.
      _writeEntry(
        register,
        day: 2,
        slug: 'replacement',
        obsoletes: const ['old-rule'],
      );
      final readmeBefore = readme.readAsStringSync();
      final styleBefore = style.readAsStringSync();

      const DecisionMutationService().obsolete(
        registerPath: register.path,
        repoRoot: sandbox.path,
        target: 'old-rule',
        successor: 'replacement',
      );

      final target = readRegister(
        register.path,
      ).singleWhere((entry) => entry.slug == 'old-rule');
      expect(target.status, 'superseded by replacement');
      expect(target.cachedObsoletedBy, 'replacement');
      expect(readme.readAsStringSync(), readmeBefore);
      expect(style.readAsStringSync(), styleBefore);
      final result = const DecisionLintService().lint(
        registerPath: register.path,
        repoRoot: sandbox.path,
      );
      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });
  });
}

File _writeEntry(
  Directory register, {
  required int day,
  required String slug,
  List<String> obsoletes = const [],
}) {
  final date = '2026-01-${day.toString().padLeft(2, '0')}';
  return File(p.join(register.path, '$date-$slug.md'))..writeAsStringSync('''
---
status: accepted
date: $date
decision-makers: [fixture]
register:
  spec: 1
  slug: $slug
  surfaces: ["lib/**"]
  obsoletes: [${obsoletes.join(', ')}]
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $slug

A fixture decision body.
''');
}
