import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _orgRegister =
    'test/fixtures/search_registers/memento-engineering/docs/decisions';
const _malformedRegister =
    'test/fixtures/index_registers/malformed_repo/docs/decisions';

void main() {
  test('bare command searches one register without a station', () async {
    final localDocs = Directory('docs');
    try {
      final register = p.join(localDocs.path, 'decisions');
      Directory(register).createSync(recursive: true);
      _writeEntry(register);

      final output = StringBuffer();
      final runner = CommandRunner<int>('decisions', 'fixture')
        ..addCommand(DecisionSearchCommand(output: output));

      expect(await runner.run(<String>['search', 'publish', 'release']), 0);
      expect(output.toString(), contains('decisions#publish-policy'));
      expect(output.toString(), contains('[accepted] 2026-04-01'));
      expect(output.toString(), contains('title: Publish release artifacts'));
    } finally {
      if (localDocs.existsSync()) localDocs.deleteSync(recursive: true);
    }
  });

  test('json lines carry schema-valid bounded hit objects', () async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = CommandRunner<int>('decisions', 'fixture')
      ..addCommand(
        DecisionSearchCommand(
          registerPaths: () => const <String>[_orgRegister],
          output: output,
          error: errors,
        ),
      );

    expect(
      await runner.run(<String>['search', '--json', 'publish', 'prerelease']),
      0,
    );
    final hits = const LineSplitter()
        .convert(output.toString())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList(growable: false);
    final schema = JsonSchema.create(
      jsonDecode(
            File(
              '../../../schema/decision-search-hit.schema.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>,
    );

    expect(hits, hasLength(2));
    expect(errors.toString(), isEmpty);
    for (final hit in hits) {
      expect(schema.validate(hit).isValid, isTrue);
      expect(hit.keys, <String>[
        'spec',
        'slug',
        'register',
        'path',
        'status',
        'date',
        'field',
        'snippet',
      ]);
      expect((hit['snippet'] as String).length, lessThanOrEqualTo(160));
      expect(hit['snippet'], isNot(anyOf(contains('\n'), contains('\r'))));
    }
  });

  test('invalid search inputs are refused without output', () async {
    var resolverCalls = 0;

    Future<void> expectRefused(List<String> arguments) async {
      final output = StringBuffer();
      final runner = CommandRunner<int>('decisions', 'fixture')
        ..addCommand(
          DecisionSearchCommand(
            registerPaths: () {
              resolverCalls++;
              return const <String>[_orgRegister];
            },
            output: output,
            error: StringBuffer(),
          ),
        );
      await expectLater(
        runner.run(<String>['search', ...arguments]),
        throwsA(isA<UsageException>()),
      );
      expect(output.toString(), isEmpty);
    }

    await expectRefused(const <String>[]);
    await expectRefused(const <String>['--date-from', '2026-02-30', 'policy']);
    await expectRefused(const <String>[
      '--date-from',
      '2026-04-02',
      '--date-through',
      '2026-04-01',
      'policy',
    ]);
    expect(resolverCalls, 0);

    final output = StringBuffer();
    final emptyRunner = CommandRunner<int>('decisions', 'fixture')
      ..addCommand(
        DecisionSearchCommand(
          registerPaths: () {
            resolverCalls++;
            return const <String>[];
          },
          output: output,
          error: StringBuffer(),
        ),
      );
    await expectLater(
      emptyRunner.run(<String>['search', 'policy']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
    expect(resolverCalls, 1);
    expect(output.toString(), isEmpty);
  });

  test(
    'human output distinguishes a clean miss from incomplete coverage',
    () async {
      final cleanOutput = StringBuffer();
      final cleanErrors = StringBuffer();
      final cleanRunner = CommandRunner<int>('decisions', 'fixture')
        ..addCommand(
          DecisionSearchCommand(
            registerPaths: () => const <String>[_orgRegister],
            output: cleanOutput,
            error: cleanErrors,
          ),
        );
      expect(await cleanRunner.run(<String>['search', 'no-such-term']), 0);
      expect(cleanOutput.toString(), contains('0 hit(s) across 1 register(s)'));
      expect(cleanErrors.toString(), isEmpty);

      final incompleteOutput = StringBuffer();
      final incompleteErrors = StringBuffer();
      final incompleteRunner = CommandRunner<int>('decisions', 'fixture')
        ..addCommand(
          DecisionSearchCommand(
            registerPaths: () => const <String>[_malformedRegister],
            output: incompleteOutput,
            error: incompleteErrors,
          ),
        );
      expect(await incompleteRunner.run(<String>['search', 'no-such-term']), 0);
      expect(incompleteOutput.toString(), contains('0 hit(s)'));
      expect(incompleteErrors.toString(), contains('[entry.schema]'));
    },
  );
}

void _writeEntry(String register) {
  File(p.join(register, '2026-04-01-publish-policy.md')).writeAsStringSync('''
---
status: accepted
date: 2026-04-01
decision-makers: [fixture]
register:
  spec: 1
  slug: publish-policy
  surfaces: ["lib/**"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Publish release artifacts
''');
}
