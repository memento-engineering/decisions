import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

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

  test('both hosts carry their own agent instructions', () {
    final grouped = DecisionsCommand(output: StringBuffer());
    final runner = DecisionsCommandRunner(output: StringBuffer());

    for (final verb in ['prime', 'guide', 'skills']) {
      expect(grouped.subcommands.keys, contains(verb));
      expect(runner.commands.keys, contains(verb));
    }
  });

  for (final args in [
    ['prime'],
    ['guide'],
    ['guide', 'ratify'],
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
    });
  }

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
