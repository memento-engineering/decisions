import 'dart:io';

import 'package:args/command_runner.dart';
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

void main() {
  late Directory sandbox;
  late Directory register;
  const linter = DecisionLintService();

  /// A roster whose register `bravo` carries [entries].
  DecisionRoster rosterOfBravo(List<DecisionEntry> entries) =>
      FakeDecisionRoster([
        DecisionRegisterSnapshot(
          originRegister: 'bravo',
          originPath: 'bravo/docs/decisions',
          entries: entries,
        ),
      ]);

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decision-cross-register-');
    register = Directory(p.join(sandbox.path, 'alpha', 'docs', 'decisions'))
      ..createSync(recursive: true);
    File(p.join(sandbox.path, 'alpha', 'lib', 'fixture.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Fixture {}\n');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  group('lint resolves cross-register edges through the roster', () {
    test('a cached qualified updater the roster confirms is valid', () {
      _writeEntry(register, slug: 'x', updatedBy: const ['bravo#y']);
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', updates: const ['alpha#x']),
      ]);

      final result = DecisionLintService(roster: roster).lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });

    test('a missing qualified updater is a named mismatch', () {
      _writeEntry(register, slug: 'x');
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', updates: const ['alpha#x']),
      ]);

      final result = DecisionLintService(roster: roster).lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.ruleId == DecisionLintRules.forceUpdatedBy,
      );
      expect(diagnostic.file, endsWith('2026-02-01-x.md'));
      expect(diagnostic.message, 'cached updated-by does not match bravo#y');
    });

    test('a cached qualified updater the roster contradicts is a '
        'named mismatch', () {
      _writeEntry(register, slug: 'x', updatedBy: const ['bravo#y']);
      final roster = rosterOfBravo([_foreignEntry(slug: 'y')]);

      final result = DecisionLintService(roster: roster).lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      expect(
        result.diagnostics
            .where((item) => item.ruleId == DecisionLintRules.forceUpdatedBy)
            .map((item) => item.message),
        ['cached updated-by does not match '],
      );
    });

    test('a cached reference into a register the roster lacks is exempt', () {
      _writeEntry(
        register,
        slug: 'x',
        updatedBy: const ['charlie#absent-one', 'charlie#absent-two'],
      );

      final result = linter.lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });

    test('a cross-register obsoleter settles status and the cache', () {
      _writeEntry(
        register,
        slug: 'x',
        status: 'superseded by bravo#y',
        obsoletedBy: 'bravo#y',
      );
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', obsoletes: const ['alpha#x']),
      ]);

      final result = DecisionLintService(roster: roster).lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });

    test('an authored reference the roster cannot resolve is named', () {
      _writeEntry(register, slug: 'x', updates: const ['bravo#absent']);
      final roster = rosterOfBravo([_foreignEntry(slug: 'y')]);

      final result = DecisionLintService(roster: roster).lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      final diagnostic = result.diagnostics.singleWhere(
        (item) => item.ruleId == DecisionLintRules.edgeDanglingCrossRegister,
      );
      expect(
        diagnostic.message,
        'authored reference "bravo#absent" does not resolve in roster register "bravo"',
      );
    });

    test('an authored reference into a register the roster lacks is '
        'exempt', () {
      _writeEntry(register, slug: 'x', updates: const ['charlie#absent']);

      final result = linter.lint(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
      );

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });
  });

  group('force mutations accept a qualified successor', () {
    test('update writes exactly the qualified cache', () {
      final target = _writeEntry(register, slug: 'x');
      final bodyBefore = _bodyBytes(target);
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', updates: const ['alpha#x']),
      ]);

      DecisionMutationService(roster: roster).update(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
        target: 'x',
        successor: 'bravo#y',
      );

      final changed = parseEntry(target.path);
      expect(changed.cachedUpdatedBy, ['bravo#y']);
      expect(changed.status, 'accepted');
      expect(changed.cachedObsoletedBy, isNull);
      expect(changed.updates, isEmpty);
      expect(changed.surfaces, ['lib/**']);
      expect(_bodyBytes(target), orderedEquals(bodyBefore));
    });

    test('update merges local and qualified updaters', () {
      final target = _writeEntry(register, slug: 'x');
      _writeEntry(register, slug: 'local', updates: const ['x'], day: 2);
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', updates: const ['alpha#x']),
      ]);

      DecisionMutationService(roster: roster).update(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
        target: 'x',
        successor: 'bravo#y',
      );

      expect(parseEntry(target.path).cachedUpdatedBy, ['bravo#y', 'local']);
    });

    test('obsolete records the qualified successor in status and cache', () {
      final target = _writeEntry(register, slug: 'x');
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', obsoletes: const ['alpha#x']),
      ]);

      DecisionMutationService(roster: roster).obsolete(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
        target: 'x',
        successor: 'bravo#y',
      );

      final changed = parseEntry(target.path);
      expect(changed.status, 'superseded by bravo#y');
      expect(changed.cachedObsoletedBy, 'bravo#y');
      expect(
        DecisionLintService(roster: roster)
            .lint(
              registerPath: register.path,
              repoRoot: p.join(sandbox.path, 'alpha'),
            )
            .isClean,
        isTrue,
      );
    });

    test('vacate accepts a qualified successor', () {
      final target = _writeEntry(register, slug: 'x');
      final roster = rosterOfBravo([_foreignEntry(slug: 'y')]);

      DecisionMutationService(roster: roster).vacate(
        registerPath: register.path,
        repoRoot: p.join(sandbox.path, 'alpha'),
        target: 'x',
        successor: 'bravo#y',
      );

      expect(parseEntry(target.path).status, 'deprecated');
    });

    test('a qualified successor outside the roster refuses without '
        'writing', () {
      final target = _writeEntry(register, slug: 'x');
      final before = target.readAsBytesSync();
      final roster = rosterOfBravo([
        _foreignEntry(slug: 'y', updates: const ['alpha#x']),
      ]);

      expect(
        () => DecisionMutationService(roster: roster).update(
          registerPath: register.path,
          repoRoot: p.join(sandbox.path, 'alpha'),
          target: 'x',
          successor: 'charlie#z',
        ),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            'unknown successor register "charlie"; it is not in this roster',
          ),
        ),
      );
      expect(target.readAsBytesSync(), orderedEquals(before));
    });

    test('a qualified successor absent from its roster register refuses', () {
      final target = _writeEntry(register, slug: 'x');
      final before = target.readAsBytesSync();
      final roster = rosterOfBravo([_foreignEntry(slug: 'y')]);

      expect(
        () => DecisionMutationService(roster: roster).update(
          registerPath: register.path,
          repoRoot: p.join(sandbox.path, 'alpha'),
          target: 'x',
          successor: 'bravo#absent',
        ),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            'unknown successor "bravo#absent" in roster register "bravo"',
          ),
        ),
      );
      expect(target.readAsBytesSync(), orderedEquals(before));
    });

    test('a qualified successor with no authored edge refuses', () {
      final target = _writeEntry(register, slug: 'x');
      final before = target.readAsBytesSync();
      final roster = rosterOfBravo([_foreignEntry(slug: 'y')]);

      expect(
        () => DecisionMutationService(roster: roster).update(
          registerPath: register.path,
          repoRoot: p.join(sandbox.path, 'alpha'),
          target: 'x',
          successor: 'bravo#y',
        ),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            '"bravo#y" must author an updates edge to "x"',
          ),
        ),
      );
      expect(target.readAsBytesSync(), orderedEquals(before));
    });

    test('a successor qualified with the target register refuses', () {
      _writeEntry(register, slug: 'x');
      _writeEntry(register, slug: 'local', updates: const ['x'], day: 2);

      expect(
        () => const DecisionMutationService().update(
          registerPath: register.path,
          repoRoot: p.join(sandbox.path, 'alpha'),
          target: 'x',
          successor: 'alpha#local',
        ),
        throwsA(
          isA<DecisionMutationException>().having(
            (error) => error.message,
            'message',
            'successor "alpha#local" names this register; pass the bare slug '
                '"local"',
          ),
        ),
      );
    });
  });

  group('the roster a verb reads', () {
    test('skips absent paths and drops an ambiguous name', () {
      final other = Directory(
        p.join(sandbox.path, 'bravo', 'docs', 'decisions'),
      )..createSync(recursive: true);
      _writeEntry(other, slug: 'y', updates: const ['alpha#x']);
      final twin = Directory(
        p.join(sandbox.path, 'twin', 'alpha', 'docs', 'decisions'),
      )..createSync(recursive: true);

      final roster = DecisionRegisterRoster.fromRegisterPaths([
        register.path,
        other.path,
        p.join(sandbox.path, 'missing', 'docs', 'decisions'),
      ]);
      expect(roster.registers.map((item) => item.originRegister), [
        'alpha',
        'bravo',
      ]);

      final ambiguous = DecisionRegisterRoster.fromRegisterPaths([
        register.path,
        other.path,
        twin.path,
      ]);
      expect(ambiguous.registers.map((item) => item.originRegister), ['bravo']);
      expect(ambiguous.findRegister('alpha'), isNull);
    });

    test('lint --roster resolves a sibling register on disk', () async {
      _writeEntry(register, slug: 'x', updatedBy: const ['bravo#y']);
      final other = Directory(
        p.join(sandbox.path, 'bravo', 'docs', 'decisions'),
      )..createSync(recursive: true);
      File(p.join(sandbox.path, 'bravo', 'lib', 'fixture.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('final class Fixture {}\n');
      _writeEntry(other, slug: 'y', updates: const ['alpha#x']);

      final output = StringBuffer();
      final runner = CommandRunner<int>('station', 'fixture')
        ..addCommand(DecisionsCommand(output: output, error: StringBuffer()));

      expect(
        await runner.run(<String>[
          'decisions',
          'lint',
          register.path,
          '--repo-root',
          p.join(sandbox.path, 'alpha'),
          '--roster',
          other.path,
        ]),
        0,
      );
      expect(output.toString(), contains('clean'));
    });
  });
}

DecisionEntry _foreignEntry({
  required String slug,
  List<String> obsoletes = const [],
  List<String> updates = const [],
}) => DecisionEntry(
  file: 'bravo/docs/decisions/2026-02-01-$slug.md',
  body: '# $slug',
  status: 'accepted',
  date: '2026-02-01',
  spec: 1,
  slug: slug,
  surfaces: const ['lib/**'],
  obsoletes: obsoletes,
  updates: updates,
  cachedObsoletedBy: null,
  cachedUpdatedBy: const [],
  bead: null,
  legacyId: null,
  decisionMakers: const ['fixture'],
);

File _writeEntry(
  Directory register, {
  required String slug,
  int day = 1,
  String status = 'accepted',
  List<String> obsoletes = const [],
  List<String> updates = const [],
  String? obsoletedBy,
  List<String> updatedBy = const [],
}) {
  final date = '2026-02-${day.toString().padLeft(2, '0')}';
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
  obsoletes: [${obsoletes.join(', ')}]
  updates: [${updates.join(', ')}]
  obsoleted-by: ${obsoletedBy ?? 'null'}
  updated-by: [${updatedBy.join(', ')}]
  bead: null
  legacy-id: null
---

# $slug
''');
  return file;
}

List<int> _bodyBytes(File file) =>
    parseEntry(file.path).body.codeUnits.toList(growable: false);
