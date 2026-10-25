import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fakeGuides = [
  Guide(name: 'decide', description: 'Record: a call.', body: '# Decide\n'),
  Guide(name: 'ratify', description: 'Hold a docket.', body: '# Ratify\n'),
];

/// A standalone-shaped runner carrying only the instruction verbs, over
/// [_fakeGuides].
CommandRunner<int> _runner(StringSink output, [StringSink? error]) =>
    CommandRunner<int>('decisions', 'fixture')
      ..addCommand(PrimeCommand(output: output))
      ..addCommand(GuideCommand(output: output, guides: _fakeGuides))
      ..addCommand(
        SkillsCommand(
          output: output,
          error: error ?? StringBuffer(),
          guides: _fakeGuides,
        ),
      );

void main() {
  late Directory sandbox;
  late String register;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decisions-instructions-');
    register = p.join(sandbox.path, 'docs', 'decisions');
    Directory(register).createSync(recursive: true);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  group('prime', () {
    test('names the register, its verbs and where contracts live', () async {
      final output = StringBuffer();

      expect(await _runner(output).run(['prime', '--register', register]), 0);
      final text = output.toString();
      expect(text, contains('Register: $register\n'));
      expect(text, contains('Style guide: none'));
      expect(text, contains('  prime   this orientation\n'));
      expect(text, contains('`decisions <verb> --help`'));
      expect(text, isNot(contains('\n  help ')));
    });

    test('points at STYLE.md when the register has one', () async {
      File(p.join(register, 'STYLE.md')).writeAsStringSync('# Style\n');
      final output = StringBuffer();

      await _runner(output).run(['prime', '--register', register]);
      expect(
        output.toString(),
        contains('Style guide: ${p.join(register, 'STYLE.md')}. Read it'),
      );
    });

    test('reports a missing register plainly', () async {
      final output = StringBuffer();
      final missing = p.join(sandbox.path, 'nowhere');

      expect(await _runner(output).run(['prime', '--register', missing]), 0);
      expect(output.toString(), contains('Register: $missing not found.'));
      expect(output.toString(), isNot(contains('Style guide')));
    });

    test('stays a short orientation over the real verbs', () async {
      final output = StringBuffer();

      await DecisionsCommandRunner(output: output).run(['prime']);
      final words = output.toString().split(RegExp(r'\s+'));
      expect(words.length, lessThan(250));
      for (final verb in ['index', 'search', 'lint', 'update', 'guide']) {
        expect(output.toString(), contains('\n  $verb '));
      }
    });

    test('names the station prefix when grouped', () async {
      final output = StringBuffer();
      final station = CommandRunner<int>('station', 'fixture')
        ..addCommand(DecisionsCommand(output: output));

      await station.run(['decisions', 'prime', '--register', register]);
      expect(output.toString(), contains('`station decisions guide`'));
      expect(output.toString(), contains('\n  lint '));
    });
  });

  group('guide', () {
    test('with no topic lists every topic', () async {
      final output = StringBuffer();

      expect(await _runner(output).run(['guide']), 0);
      expect(output.toString(), contains('  decide: Record: a call.\n'));
      expect(output.toString(), contains('  ratify: Hold a docket.\n'));
    });

    test('prints the body alone when there is no STYLE.md', () async {
      final output = StringBuffer();

      expect(
        await _runner(output).run(['guide', 'decide', '--register', register]),
        0,
      );
      expect(output.toString(), '# Decide\n');
    });

    test('appends STYLE.md under a heading naming the file', () async {
      final style = p.join(register, 'STYLE.md');
      File(style).writeAsStringSync('Titles are claims.');
      final output = StringBuffer();

      await _runner(output).run(['guide', 'ratify', '--register', register]);
      expect(
        output.toString(),
        '# Ratify\n\n# Register style guide: $style\n\nTitles are claims.\n',
      );
    });

    test('an unknown topic is a usage error naming the topics', () async {
      expect(
        () => _runner(StringBuffer()).run(['guide', 'nope']),
        throwsA(
          isA<UsageException>().having(
            (error) => error.message,
            'message',
            contains('Topics: decide, ratify'),
          ),
        ),
      );
    });

    test('the binary prints the canonical skill', () async {
      final output = StringBuffer();

      await DecisionsCommandRunner(
        output: output,
      ).run(['guide', 'decide', '--register', register]);
      expect(
        output.toString(),
        bundledGuides.singleWhere((guide) => guide.name == 'decide').body,
      );
    });
  });

  group('skills install', () {
    late String skills;

    setUp(() => skills = p.join(sandbox.path, '.claude', 'skills'));

    String stub(String name) =>
        File(p.join(skills, name, 'SKILL.md')).readAsStringSync();

    test('writes one stub per guide that defers to guide', () async {
      final output = StringBuffer();

      expect(await _runner(output).run(['skills', 'install', skills]), 0);
      expect(
        stub('decide'),
        startsWith(
          '---\nname: decide\ndescription: "Record: a call."\n---\n\n'
          '$skillStubMarker\n',
        ),
      );
      expect(stub('decide'), contains('Run `decisions guide decide`'));
      expect(stub('ratify'), contains('Run `decisions guide ratify`'));
      expect(
        output.toString(),
        'wrote ${p.join(skills, 'decide', 'SKILL.md')}\n'
        'wrote ${p.join(skills, 'ratify', 'SKILL.md')}\n',
      );
    });

    test('overwrites an earlier stub', () async {
      final path = p.join(skills, 'decide', 'SKILL.md');
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('old\n$skillStubMarker\n');

      expect(
        await _runner(StringBuffer()).run(['skills', 'install', skills]),
        0,
      );
      expect(stub('decide'), skillStub(_fakeGuides.first));
    });

    test('refuses to overwrite any other file and writes nothing', () async {
      final path = p.join(skills, 'ratify', 'SKILL.md');
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('my own ratify skill\n');
      final error = StringBuffer();

      expect(
        await _runner(StringBuffer(), error).run(['skills', 'install', skills]),
        1,
      );
      expect(stub('ratify'), 'my own ratify skill\n');
      expect(File(p.join(skills, 'decide', 'SKILL.md')).existsSync(), isFalse);
      expect(error.toString(), contains('$path exists and is not a decisions'));
    });

    test('refuses a directory where a stub belongs', () async {
      Directory(
        p.join(skills, 'decide', 'SKILL.md'),
      ).createSync(recursive: true);

      expect(
        await _runner(StringBuffer()).run(['skills', 'install', skills]),
        1,
      );
    });

    test('needs exactly one directory', () async {
      expect(
        () => _runner(StringBuffer()).run(['skills', 'install']),
        throwsA(isA<UsageException>()),
      );
    });
  });
}
