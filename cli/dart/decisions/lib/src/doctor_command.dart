import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'doctor.dart';
import 'instructions_command.dart';

/// `decisions doctor`: whether this binary can work this register.
///
/// The output contract is fixed, because whatever runs the binary shims over
/// it: the first stdout line is the worst finding, the exit code is 0, 1 or
/// 2 for a worst of ok, warn or fail, and a malformed invocation is a usage
/// error.
final class DoctorCommand extends Command<int> {
  /// Creates the verb over [doctor], writing every finding to [output].
  DoctorCommand({
    required StringSink output,
    DecisionDoctor doctor = const DecisionDoctorService(),
  }) : _output = output,
       _doctor = doctor {
    argParser
      ..addOption(
        'register',
        valueHelp: 'path',
        help: 'Register to check. Defaults to <repo-root>/docs/decisions.',
      )
      ..addOption(
        'repo-root',
        defaultsTo: '.',
        help: 'Repository root the default register sits under.',
      )
      ..addOption(
        'skills',
        valueHelp: 'dir',
        help:
            'Also check the skill stubs in <dir> against what '
            '`skills install` would write.',
      )
      ..addFlag(
        'no-register',
        negatable: false,
        help: 'Inspect no register: only the binary and --skills checks run.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the schema-versioned JSON result.',
      );
  }

  final StringSink _output;
  final DecisionDoctor _doctor;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check that this binary can work this register.\n'
      '\n'
      'Checks the register exists, every entry declares a spec this binary '
      'reads, and\nevery entry parses (graph findings are `lint`\'s), notes '
      'any STYLE.md, and with\n--skills compares the stubs in <dir> to what '
      'this binary would install.\n'
      '\n'
      'The first stdout line is the worst finding, with "(and N more)" when N '
      'other\nfindings are warn or fail; one line per finding and its fix '
      'follows. Exits 0\nwhen all are ok or info, 1 when the worst is warn, 2 '
      'when it is fail; a\nmalformed invocation is a usage error (exit 64). '
      'Offline and read-only.';

  @override
  void printUsage() => _output.writeln(usage);

  @override
  int run() {
    final results = argResults!;
    if (results.rest.isNotEmpty) {
      usageException('doctor takes no positional arguments.');
    }
    final noRegister = results.flag('no-register');
    if (noRegister &&
        (results.wasParsed('register') || results.wasParsed('repo-root'))) {
      usageException(
        '--no-register inspects no register; drop --register and --repo-root.',
      );
    }
    final report = _doctor.examine(
      registerPath: noRegister
          ? null
          : results.option('register') ??
                p.normalize(
                  p.join(results.option('repo-root')!, 'docs', 'decisions'),
                ),
      skillsDirectory: results.option('skills'),
      command: commandInvocation(this),
    );
    if (results.flag('json')) {
      _output.writeln(jsonEncode(report.toJson()));
    } else {
      report.lines.forEach(_output.writeln);
    }
    return report.exitCode;
  }
}
