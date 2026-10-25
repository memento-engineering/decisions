import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _guides = [
  Guide(name: 'decide', description: 'Record a call.', body: '# Decide\n'),
  Guide(name: 'ratify', description: 'Hold a docket.', body: '# Ratify\n'),
];

const _service = DecisionDoctorService(
  version: '9.9.9',
  supportedSpec: 1,
  guides: _guides,
);

/// Records what [DoctorCommand] asked for and answers with [report].
final class FakeDecisionDoctor implements DecisionDoctor {
  FakeDecisionDoctor(this.report);

  final DoctorReport report;
  final calls = <(String?, String?, String, String)>[];

  @override
  DoctorReport examine({
    required String? registerPath,
    required String? skillsDirectory,
    required String command,
    String repoRoot = '.',
  }) {
    calls.add((registerPath, skillsDirectory, command, repoRoot));
    return report;
  }
}

String _entry(String slug, {int spec = 1, String extraKey = ''}) =>
    '''
---
status: accepted
date: 2026-01-01
decision-makers: [fixture]
register:
  spec: $spec
  slug: $slug
  surfaces: ["lib/**"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
$extraKey---

# $slug
''';

void main() {
  late Directory sandbox;
  late String register;
  late String skills;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decisions-doctor-');
    register = p.join(sandbox.path, 'docs', 'decisions');
    skills = p.join(sandbox.path, 'skills');
    Directory(register).createSync(recursive: true);
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  void write(String path, String content) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  void entry(String slug, {int spec = 1, String extraKey = ''}) => write(
    p.join(register, '2026-01-01-$slug.md'),
    _entry(slug, spec: spec, extraKey: extraKey),
  );

  DoctorReport examine({
    String? registerPath,
    String? skillsDirectory,
    String repoRoot = '.',
  }) => _service.examine(
    registerPath: registerPath,
    skillsDirectory: skillsDirectory,
    command: 'decisions',
    repoRoot: repoRoot,
  );

  DoctorFinding only(DoctorReport report, String check) =>
      report.findings.singleWhere((finding) => finding.check == check);

  group('register checks', () {
    test('a sound register is ok and headlines the register', () {
      entry('one');
      entry('two');
      write(p.join(register, 'README.md'), '# Not an entry\n');

      final report = examine(registerPath: register);

      expect(report.exitCode, 0);
      expect(report.worst.severity, DoctorSeverity.ok);
      expect(report.headline, 'ok register: $register holds 2 entries');
      expect(report.findings.map((finding) => finding.check), [
        'binary',
        'register',
        'spec',
        'parse',
        'style',
      ]);
      expect(
        only(report, 'binary').message,
        'decisions 9.9.9 reads spec <= 1, writes spec 1',
      );
      expect(only(report, 'parse').message, contains('`decisions lint`'));
    });

    test('a missing register fails and says how to start one', () {
      final missing = p.join(sandbox.path, 'nowhere');

      final report = examine(registerPath: missing);

      expect(report.exitCode, 2);
      expect(report.headline, 'fail register: $missing not found');
      expect(report.worst.hint, contains('`decisions new`'));
      expect(report.findings.map((finding) => finding.check), [
        'binary',
        'register',
      ]);
    });

    test('a file where the register belongs fails', () {
      final file = p.join(sandbox.path, 'file');
      write(file, 'x');

      expect(examine(registerPath: file).worst.message, contains('directory'));
    });

    test('an entry newer than this binary fails spec, not parse', () {
      entry('one');
      // A spec-2 entry may carry keys spec 1 rejects; that is still a spec
      // finding, and the fix is to upgrade.
      entry('future', spec: 2, extraKey: '  shiny: true\n');

      final report = examine(registerPath: register);

      expect(report.exitCode, 2);
      final spec = only(report, 'spec');
      expect(spec.severity, DoctorSeverity.fail);
      expect(spec.message, contains('1 entry declares a spec newer than 1'));
      expect(spec.message, contains('spec 2 in'));
      expect(spec.hint, contains('brew install memento-engineering/tap'));
      expect(spec.hint, contains('/releases'));
      expect(only(report, 'parse').severity, DoctorSeverity.ok);
      expect(report.headline, startsWith('fail spec: '));
    });

    test('an unparseable entry fails parse and points at lint', () {
      write(p.join(register, '2026-01-01-broken.md'), 'no front matter\n');

      final report = examine(registerPath: register);
      final parse = only(report, 'parse');

      expect(report.exitCode, 2);
      expect(parse.severity, DoctorSeverity.fail);
      expect(parse.message, contains('no YAML front matter'));
      expect(parse.hint, '`decisions lint $register` names each one');
    });

    test('the lint the parse hint names carries a non-default repo root', () {
      write(p.join(register, '2026-01-01-broken.md'), 'no front matter\n');

      final parse = only(
        examine(registerPath: register, repoRoot: sandbox.path),
        'parse',
      );

      expect(
        parse.hint,
        '`decisions lint $register --repo-root ${sandbox.path}` names each one',
      );
    });

    test('malformed front matter YAML fails parse without crashing', () {
      write(
        p.join(register, '2026-01-01-bad-yaml.md'),
        '---\nstatus: [unclosed\n---\n\n# Bad\n',
      );

      final parse = only(examine(registerPath: register), 'parse');
      expect(parse.severity, DoctorSeverity.fail);
      expect(parse.message, contains('front matter'));

      // The lint the hint names reports the same entry instead of crashing.
      final lint = const DecisionLintService().lint(
        registerPath: register,
        repoRoot: sandbox.path,
      );
      expect(lint.diagnostics.map((diagnostic) => diagnostic.ruleId), [
        DecisionLintRules.entrySchema,
      ]);
      expect(lint.diagnostics.single.message, contains('front matter'));
    });

    test('the headline counts the other findings needing action', () {
      entry('future', spec: 2);
      write(p.join(register, '2026-01-01-broken.md'), 'no front matter\n');

      final report = examine(registerPath: register, skillsDirectory: skills);

      // spec fail headlines; parse fail and two missing stubs follow.
      expect(report.headline, endsWith(' (and 3 more)'));
      expect(report.headline, startsWith('fail spec: '));
    });

    test('STYLE.md is noted either way and never judged', () {
      entry('one');
      expect(
        only(examine(registerPath: register), 'style').message,
        'no '
        '${p.join(register, 'STYLE.md')}; the guides alone shape entry '
        'bodies',
      );

      write(p.join(register, 'STYLE.md'), '# Style\n');
      final style = only(examine(registerPath: register), 'style');
      expect(style.severity, DoctorSeverity.info);
      expect(style.message, 'style guide ${p.join(register, 'STYLE.md')}');
    });

    test('no register inspects only the binary', () {
      final report = examine();

      expect(report.findings.map((finding) => finding.check), ['binary']);
      expect(report.register, isNull);
      expect(report.exitCode, 0);
    });

    test('finishes well under a second on the self-hosted register', () {
      final watch = Stopwatch()..start();
      final report = const DecisionDoctorService().examine(
        registerPath: '../../../docs/decisions',
        skillsDirectory: null,
        command: 'decisions',
      );

      expect(report.exitCode, 0);
      expect(watch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('skills checks', () {
    String stubPath(String name) => p.join(skills, name, 'SKILL.md');

    test('stubs this binary would write are ok', () {
      for (final guide in _guides) {
        write(stubPath(guide.name), skillStub(guide));
      }

      final report = examine(skillsDirectory: skills);

      expect(report.exitCode, 0);
      expect(
        report.findings
            .where((finding) => finding.check == 'skills')
            .map((finding) => finding.severity),
        [DoctorSeverity.ok, DoctorSeverity.ok],
      );
    });

    test('a stub naming another invocation differs', () {
      write(stubPath('decide'), skillStub(_guides[0], command: 'station x'));
      write(stubPath('ratify'), skillStub(_guides[1]));

      final report = examine(skillsDirectory: skills);

      expect(report.exitCode, 1);
      expect(
        report.headline,
        'warn skills: ${stubPath('decide')} differs from the stub this '
        'binary writes',
      );
      expect(report.worst.hint, contains('`decisions skills install $skills`'));
    });

    test('a guide with no stub warns, as does a missing directory', () {
      final report = examine(skillsDirectory: skills);

      expect(report.exitCode, 1);
      expect(report.headline, endsWith(' (and 1 more)'));
      expect(report.worst.message, contains('no stub for guide decide'));
    });

    test('a file where the skills directory belongs is not a fixable stub', () {
      write(skills, 'x');

      final report = examine(skillsDirectory: skills);
      final finding = only(report, 'skills');

      expect(report.exitCode, 1);
      expect(
        finding.message,
        '$skills is not a directory, so it holds no stubs',
      );
      expect(
        finding.hint,
        contains('pass --skills naming the skills directory'),
      );
      expect(finding.hint, contains('move $skills aside'));
    });

    test('an adopter skill at a guide path is info, never judged', () {
      write(stubPath('decide'), '---\nname: decide\n---\nmine\n');
      write(stubPath('ratify'), skillStub(_guides[1]));

      final report = examine(skillsDirectory: skills);
      final decide = report.findings[1];

      expect(report.exitCode, 0);
      expect(decide.severity, DoctorSeverity.info);
      expect(decide.message, contains('adopter\'s own skill'));
      expect(decide.hint, isNull);
    });

    test('a stub for a guide this binary lacks is a dead pointer', () {
      for (final guide in _guides) {
        write(stubPath(guide.name), skillStub(guide));
      }
      const gone = Guide(name: 'retired', description: 'Gone.', body: '');
      write(stubPath('retired'), skillStub(gone));

      final report = examine(skillsDirectory: skills);

      expect(report.exitCode, 2);
      expect(report.worst.message, contains('guide retired'));
      expect(report.worst.hint, DecisionDoctorService.upgradeHint);
    });

    test('other adopter skills are listed once as info', () {
      for (final guide in _guides) {
        write(stubPath(guide.name), skillStub(guide));
      }
      write(stubPath('zeta'), 'mine\n');
      write(stubPath('alpha'), 'mine\n');
      Directory(p.join(skills, 'empty')).createSync();

      final report = examine(skillsDirectory: skills);

      expect(report.exitCode, 0);
      expect(
        report.findings.last.message,
        '2 other skills in $skills are the adopter\'s own: alpha, zeta',
      );
    });
  });

  group('doctor command', () {
    CommandRunner<int> runner(StringSink output, DecisionDoctor doctor) =>
        CommandRunner<int>('decisions', 'fixture')
          ..addCommand(DoctorCommand(output: output, doctor: doctor));

    final report = DoctorReport(
      version: '9.9.9',
      supportedSpec: 1,
      register: 'r',
      findings: const [
        DoctorFinding(
          check: 'spec',
          severity: DoctorSeverity.fail,
          message: 'too new',
          hint: 'upgrade',
        ),
        DoctorFinding(
          check: 'style',
          severity: DoctorSeverity.info,
          message: 'm',
        ),
        DoctorFinding(
          check: 'parse',
          severity: DoctorSeverity.warn,
          message: 'odd',
          hint: 'look',
        ),
      ],
    );

    test(
      'the first line is the worst finding, then each with its hint',
      () async {
        final output = StringBuffer();

        final code = await runner(
          output,
          FakeDecisionDoctor(report),
        ).run(['doctor']);

        expect(code, 2);
        expect(
          output.toString(),
          'fail spec: too new (and 1 more)\n'
          '  fail spec: too new; fix: upgrade\n'
          '  info style: m\n'
          '  warn parse: odd; fix: look\n',
        );
      },
    );

    test('the register defaults under --repo-root', () async {
      final doctor = FakeDecisionDoctor(report);

      await runner(StringBuffer(), doctor).run(['doctor']);
      await runner(StringBuffer(), doctor).run(['doctor', '--repo-root', 'x']);
      await runner(
        StringBuffer(),
        doctor,
      ).run(['doctor', '--register', 'r', '--skills', 's']);
      await runner(StringBuffer(), doctor).run(['doctor', '--no-register']);

      expect(doctor.calls, [
        ('docs/decisions', null, 'decisions', '.'),
        (p.join('x', 'docs', 'decisions'), null, 'decisions', 'x'),
        ('r', 's', 'decisions', '.'),
        (null, null, 'decisions', '.'),
      ]);
    });

    test('a station host names its own invocation', () async {
      final doctor = FakeDecisionDoctor(report);
      final station = CommandRunner<int>('station', 'fixture')
        ..addCommand(
          _Group(DoctorCommand(output: StringBuffer(), doctor: doctor)),
        );

      await station.run(['decisions', 'doctor']);
      expect(doctor.calls.single.$3, 'station decisions');
    });

    test('--no-register with a register option is a usage error', () {
      for (final option in ['--register', '--repo-root']) {
        expect(
          () => runner(
            StringBuffer(),
            FakeDecisionDoctor(report),
          ).run(['doctor', '--no-register', option, 'x']),
          throwsA(isA<UsageException>()),
        );
      }
      expect(
        () => runner(
          StringBuffer(),
          FakeDecisionDoctor(report),
        ).run(['doctor', 'extra']),
        throwsA(isA<UsageException>()),
      );
    });

    test('json validates against its schema', () async {
      entry('one');
      write(p.join(skills, 'decide', 'SKILL.md'), 'mine\n');
      final schema = JsonSchema.create(
        jsonDecode(
              File(
                '../../../schema/doctor-result.schema.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>,
      );

      for (final args in [
        ['--register', register, '--skills', skills],
        ['--register', p.join(sandbox.path, 'nowhere')],
        ['--no-register'],
      ]) {
        final output = StringBuffer();
        final code = await runner(
          output,
          _service,
        ).run(['doctor', '--json', ...args]);
        final Object? decoded = jsonDecode(output.toString());

        expect(schema.validate(decoded).isValid, isTrue, reason: '$args');
        expect((decoded as Map<String, Object?>)['exitCode'], code);
        expect(decoded['schemaVersion'], DoctorReport.schemaVersion);
      }
    });

    test('help states the contract and names no harness', () {
      final usage = runner(
        StringBuffer(),
        FakeDecisionDoctor(report),
      ).commands['doctor']!.usage;

      expect(usage, contains('The first stdout line is the worst finding'));
      expect(usage, contains('(and N more)'));
      expect(usage, contains('Exits 0'));
      expect(usage, contains('exit 64'));
      expect(usage, contains('--no-register'));
      for (final harness in ['Gas City', 'gc ', '--gc', 'GC_']) {
        expect(usage, isNot(contains(harness)));
      }
    });

    test('prime lists doctor with its cue', () async {
      final output = StringBuffer();

      await DecisionsCommandRunner(output: output).run(['prime']);
      expect(
        output.toString(),
        contains(
          '\n  doctor          check this binary can work this register',
        ),
      );
    });

    test('the standalone binary exits 64 on a usage error', () async {
      final output = StringBuffer();
      final error = StringBuffer();

      expect(
        await DecisionsCommandRunner(
          output: output,
          error: error,
        ).run(['doctor', '--no-register', '--register', 'x']),
        64,
      );
      expect(output.toString(), isEmpty);
      expect(error.toString(), contains('--no-register'));
    });
  });
}

/// A `decisions` group carrying only [verb], to check invocation naming.
final class _Group extends Command<int> {
  _Group(Command<int> verb) {
    addSubcommand(verb);
  }

  @override
  String get name => 'decisions';

  @override
  String get description => 'fixture';
}
