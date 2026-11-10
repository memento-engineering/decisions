import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _selfHostedRegister = '../../../docs/decisions';

void main() {
  test('the runner exposes every grouped verb at top level', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    expect(runner.commands.keys, containsAll(grouped.subcommands.keys));
  });

  test('both hosts carry the new verb', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    expect(grouped.subcommands['new'], isA<DecisionNewCommand>());
    expect(runner.commands['new'], isA<DecisionNewCommand>());
  });

  test('both hosts carry the doctor verb', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    expect(grouped.subcommands['doctor'], isA<DoctorCommand>());
    expect(runner.commands['doctor'], isA<DoctorCommand>());
  });

  test('both hosts carry their own agent instructions', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    for (final verb in ['prime', 'guide', 'skills']) {
      expect(grouped.subcommands.keys, contains(verb));
      expect(runner.commands.keys, contains(verb));
    }
  });

  for (final args in [
    ['prime', '--register', _selfHostedRegister],
    ['guide'],
    ['guide', 'ratify'],
    ['doctor', '--repo-root', '../../..'],
  ]) {
    test('${args.join(' ')} gives the grouped command\'s output', () async {
      final groupedOutput = StringBuffer();
      final grouped = CommandRunner<int>('decisions', 'fixture')
        ..addCommand(DecisionsCommand(output: groupedOutput));
      final standaloneOutput = StringBuffer();

      await grouped.run(['decisions', ...args]);
      await DecisionsCommandRunner(output: standaloneOutput).run(args);

      expect(
        standaloneOutput.toString(),
        groupedOutput.toString().replaceAll('decisions decisions', 'decisions'),
      );
      if (args.first == 'prime') {
        for (final output in [
          groupedOutput.toString(),
          standaloneOutput.toString(),
        ]) {
          expect(output, contains('Register: $_selfHostedRegister\n'));
          expect(
            output,
            contains(
              'Style guide: ${p.join(_selfHostedRegister, 'STYLE.md')}. Read it',
            ),
          );
        }
      }
    });
  }

  test('both hosts carry the resurface verb', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    expect(grouped.subcommands['resurface']?.name, 'resurface');
    expect(runner.commands['resurface']?.name, 'resurface');
  });

  test('both hosts carry the render verb', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    expect(
      grouped.subcommands['render'],
      isA<RenderCommand>().having((verb) => verb.name, 'name', 'render'),
    );
    expect(
      runner.commands['render'],
      isA<RenderCommand>().having((verb) => verb.name, 'name', 'render'),
    );
  });

  test('resurface gives the grouped command\'s output', () async {
    final sandboxes = [
      for (var i = 0; i < 2; i++)
        Directory.systemTemp.createTempSync('decisions-resurface-runner-'),
    ];
    addTearDown(() {
      for (final sandbox in sandboxes) {
        if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
      }
    });
    final entries = <File>[];
    for (final sandbox in sandboxes) {
      File(p.join(sandbox.path, 'src', 'fixture.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('final class Fixture {}\n');
      entries.add(
        File(p.join(sandbox.path, 'docs', 'decisions', '2026-01-01-alpha.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync('''
---
status: accepted
date: 2026-01-01
decision-makers: [fixture]
register:
  spec: 1
  slug: alpha
  surfaces: ["lib/**"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# alpha

A fixture decision body.
'''),
      );
    }
    List<String> args(Directory sandbox) => [
      'resurface',
      '--from',
      'lib/**',
      '--to',
      'src/**',
      '--register',
      p.join(sandbox.path, 'docs', 'decisions'),
      '--repo-root',
      sandbox.path,
    ];
    final groupedOutput = StringBuffer();
    final station = CommandRunner<int>('station', 'fixture')
      ..addCommand(DecisionsCommand(output: groupedOutput));
    final standaloneOutput = StringBuffer();

    final groupedCode = await station.run(['decisions', ...args(sandboxes[0])]);
    final standaloneCode = await DecisionsCommandRunner(
      output: standaloneOutput,
    ).run(args(sandboxes[1]));

    expect(groupedCode, 0);
    expect(standaloneCode, groupedCode);
    expect(groupedOutput.toString(), 'alpha\n');
    expect(standaloneOutput.toString(), groupedOutput.toString());
    expect(
      entries[1].readAsBytesSync(),
      orderedEquals(entries[0].readAsBytesSync()),
    );
    expect(entries[0].readAsStringSync(), contains('surfaces: ["src/**"]'));
  });

  test('--version prints the artifact version and the spec', () async {
    final output = StringBuffer();
    final code = await DecisionsCommandRunner(
      output: output,
    ).run(['--version']);

    expect(code, 0);
    expect(
      output.toString(),
      'decisions $decisionsVersion (reads spec <= 1, writes spec 1)\n',
    );
  });

  test('the version constant matches the pubspec', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;

    expect(decisionsVersion, pubspec['version']);
  });

  for (final register in [
    'test/fixtures/dangling_register',
    '../../../docs/decisions',
  ]) {
    test('lint on $register gives the grouped command\'s verdict', () async {
      final args = ['lint', register, '--repo-root', '../../..', '--json'];
      final groupedOutput = StringBuffer();
      final grouped = CommandRunner<int>('station', 'fixture')
        ..addCommand(DecisionsCommand(output: groupedOutput));
      final standaloneOutput = StringBuffer();

      final groupedCode = await grouped.run(['decisions', ...args]);
      final standaloneCode = await DecisionsCommandRunner(
        output: standaloneOutput,
      ).run(args);

      expect(standaloneCode, groupedCode);
      expect(standaloneOutput.toString(), groupedOutput.toString());
    });
  }

  test('a malformed invocation exits 64 with usage on stderr', () async {
    final output = StringBuffer();
    final error = StringBuffer();
    final runner = DecisionsCommandRunner(output: output, error: error);

    expect(await runner.run(['no-such-verb']), 64);
    expect(await runner.run(['lint']), 64);
    expect(output.toString(), isEmpty);
    expect(error.toString(), contains('Usage: decisions'));
  });

  test('bare --help succeeds', () async {
    final output = StringBuffer();
    final runner = DecisionsCommandRunner(output: output);

    expect(await runner.run(['--help']), 0);
    expect(output.toString(), contains('Usage: decisions <command>'));
  });
}
