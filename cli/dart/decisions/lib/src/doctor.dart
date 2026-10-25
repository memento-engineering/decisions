import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'entry.dart';
import 'guide.dart';
import 'instructions_command.dart';
import 'lint.dart';
import 'version.dart';

/// How bad one [DoctorFinding] is, in ascending order.
///
/// [info] sits below [ok]: it describes the setup and never colours a
/// verdict, so a run of only `ok` and `info` findings headlines an `ok` one.
enum DoctorSeverity {
  /// A fact about the setup that needs no action.
  info,

  /// The check passed.
  ok,

  /// The binary can work the register, but something is out of step.
  warn,

  /// The binary cannot work the register (or a skill stub) as it stands.
  fail,
}

/// One check's verdict: what was checked, how it went, and how to fix it.
final class DoctorFinding {
  /// Creates a finding for [check] at [severity].
  const DoctorFinding({
    required this.check,
    required this.severity,
    required this.message,
    this.hint,
  });

  /// The check that produced this finding: `binary`, `register`, `spec`,
  /// `parse`, `style` or `skills`.
  final String check;

  /// How bad the finding is.
  final DoctorSeverity severity;

  /// A one-line reason.
  final String message;

  /// A one-line fix, or `null` when there is nothing to do.
  final String? hint;

  /// The finding as one line, without its hint.
  String get summary => '${severity.name} $check: $message';

  /// The finding's JSON object, as `schema/doctor-result.schema.json` pins.
  Map<String, Object?> toJson() => {
    'check': check,
    'severity': severity.name,
    'message': message,
    'hint': hint,
  };
}

/// Everything one `decisions doctor` run found, in check order.
final class DoctorReport {
  /// Creates a report over [findings], which must not be empty.
  DoctorReport({
    required this.version,
    required this.supportedSpec,
    required this.register,
    required Iterable<DoctorFinding> findings,
  }) : findings = List<DoctorFinding>.unmodifiable(findings) {
    if (this.findings.isEmpty) {
      throw ArgumentError.value(findings, 'findings', 'must not be empty');
    }
  }

  /// The version of `schema/doctor-result.schema.json` that [toJson] emits.
  static const schemaVersion = 1;

  /// The artifact version of the binary that ran the checks.
  final String version;

  /// The newest spec the binary reads, which is also the spec it writes.
  final int supportedSpec;

  /// The register examined, or `null` when the run inspected none.
  final String? register;

  /// Every finding, in check order.
  final List<DoctorFinding> findings;

  /// The first finding of the highest severity.
  DoctorFinding get worst => findings.reduce(
    (worst, next) => next.severity.index > worst.severity.index ? next : worst,
  );

  /// The process exit code: 0 when the worst finding is `ok` or `info`, 1
  /// when it is `warn`, 2 when it is `fail`.
  int get exitCode => switch (worst.severity) {
    DoctorSeverity.info || DoctorSeverity.ok => 0,
    DoctorSeverity.warn => 1,
    DoctorSeverity.fail => 2,
  };

  /// The number of findings other than [worst] at `warn` or `fail`.
  int get othersNeedingAction {
    final headline = worst;
    return findings
        .where(
          (finding) =>
              !identical(finding, headline) &&
              finding.severity.index >= DoctorSeverity.warn.index,
        )
        .length;
  }

  /// The first output line: [worst], then `(and N more)` when N other
  /// findings are at `warn` or `fail`.
  String get headline {
    final more = othersNeedingAction;
    return more == 0 ? worst.summary : '${worst.summary} (and $more more)';
  }

  /// The human output: [headline], then one line per finding with its hint.
  List<String> get lines => [
    headline,
    for (final finding in findings)
      '  ${finding.severity.name.padRight(4)} ${finding.check}: '
          '${finding.message}'
          '${finding.hint == null ? '' : '; fix: ${finding.hint}'}',
  ];

  /// The schema-versioned JSON result.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'version': version,
    'supportedSpec': supportedSpec,
    'register': register,
    'worst': worst.severity.name,
    'exitCode': exitCode,
    'findings': [for (final finding in findings) finding.toJson()],
  };
}

/// UI-drivable contract for `decisions doctor`.
abstract interface class DecisionDoctor {
  /// Checks whether this binary can work the register at [registerPath]
  /// and, when [skillsDirectory] is given, the skill stubs in it.
  ///
  /// A `null` [registerPath] inspects no register: only the binary and
  /// skills checks run. [command] is how this binary is invoked (`decisions`,
  /// or `<station> decisions`), which is what a current stub names.
  DoctorReport examine({
    required String? registerPath,
    required String? skillsDirectory,
    required String command,
  });
}

/// The offline, bounded checks behind `decisions doctor`.
///
/// It reads files and nothing else: no network, no subprocess, and no
/// knowledge of whatever harness runs it.
final class DecisionDoctorService implements DecisionDoctor {
  /// Creates the checks for a binary at [version] that reads specs up to
  /// [supportedSpec] and carries [guides].
  const DecisionDoctorService({
    this.version = decisionsVersion,
    this.supportedSpec = DecisionLintService.supportedSpec,
    this.guides = bundledGuides,
  });

  /// The artifact version reported by the `binary` check.
  final String version;

  /// The newest spec this binary reads.
  final int supportedSpec;

  /// The guides this binary carries, whose stubs the `skills` check expects.
  final List<Guide> guides;

  /// The fix for a register or stub newer than this binary.
  static const upgradeHint =
      'upgrade decisions: brew upgrade memento-engineering/tap/decisions '
      '(first install: brew install memento-engineering/tap/decisions), or '
      'download a release from '
      'https://github.com/memento-engineering/decisions/releases';

  @override
  DoctorReport examine({
    required String? registerPath,
    required String? skillsDirectory,
    required String command,
  }) {
    final findings = <DoctorFinding>[
      DoctorFinding(
        check: 'binary',
        severity: DoctorSeverity.info,
        message:
            'decisions $version reads spec <= $supportedSpec, '
            'writes spec $supportedSpec',
      ),
      if (registerPath != null) ..._register(registerPath, command),
      if (skillsDirectory != null) ..._skills(skillsDirectory, command),
    ];
    return DoctorReport(
      version: version,
      supportedSpec: supportedSpec,
      register: registerPath,
      findings: findings,
    );
  }

  List<DoctorFinding> _register(String register, String command) {
    final type = FileSystemEntity.typeSync(register);
    if (type == FileSystemEntityType.notFound) {
      return [
        DoctorFinding(
          check: 'register',
          severity: DoctorSeverity.fail,
          message: '$register not found',
          hint:
              'run from the repository root or pass --repo-root or '
              '--register; to start one, record a first decision with '
              '`$command new`',
        ),
      ];
    }
    if (type != FileSystemEntityType.directory) {
      return [
        DoctorFinding(
          check: 'register',
          severity: DoctorSeverity.fail,
          message: '$register is not a directory',
          hint: 'pass --register naming the register directory',
        ),
      ];
    }
    final List<String> files;
    try {
      files =
          Directory(register)
              .listSync()
              .whereType<File>()
              .map((file) => p.join(register, p.basename(file.path)))
              .where(isDecisionEntryFile)
              .toList()
            ..sort();
    } on FileSystemException catch (error) {
      return [
        DoctorFinding(
          check: 'register',
          severity: DoctorSeverity.fail,
          message: 'cannot list $register: ${_reason(error)}',
          hint: 'make the register directory readable',
        ),
      ];
    }

    final newer = <(String, int)>[];
    final unparsed = <(String, String)>[];
    for (final file in files) {
      final String text;
      try {
        text = File(file).readAsStringSync();
      } on FileSystemException catch (error) {
        unparsed.add((file, 'cannot read: ${_reason(error)}'));
        continue;
      }
      final spec = _declaredSpec(text);
      if (spec != null && spec > supportedSpec) {
        // A newer spec may add keys this binary rejects; that is the spec
        // check's finding, not a parse failure.
        newer.add((file, spec));
        continue;
      }
      try {
        parseEntry(file);
      } on DecisionParseException catch (error) {
        unparsed.add((file, error.message));
      } on FormatException catch (error) {
        // Malformed YAML front matter surfaces as a YamlException.
        unparsed.add((file, 'front matter: ${error.message}'));
      } on FileSystemException catch (error) {
        unparsed.add((file, 'cannot read: ${_reason(error)}'));
      }
    }

    final style = p.join(register, 'STYLE.md');
    return [
      DoctorFinding(
        check: 'register',
        severity: DoctorSeverity.ok,
        message: '$register holds ${_entries(files.length)}',
      ),
      if (newer.isEmpty)
        DoctorFinding(
          check: 'spec',
          severity: DoctorSeverity.ok,
          message: 'every entry declares spec <= $supportedSpec',
        )
      else
        DoctorFinding(
          check: 'spec',
          severity: DoctorSeverity.fail,
          message:
              '${_entries(newer.length)} ${newer.length == 1 ? 'declares' : 'declare'} '
              'a spec newer than '
              '$supportedSpec (spec ${newer.first.$2} in ${newer.first.$1})',
          hint: upgradeHint,
        ),
      if (unparsed.isEmpty)
        DoctorFinding(
          check: 'parse',
          severity: DoctorSeverity.ok,
          message: 'every entry parses; `$command lint` checks the graph',
        )
      else
        DoctorFinding(
          check: 'parse',
          severity: DoctorSeverity.fail,
          message:
              '${_entries(unparsed.length)} '
              '${unparsed.length == 1 ? 'does' : 'do'} not parse '
              '(${unparsed.first.$1}: ${unparsed.first.$2})',
          hint: '`$command lint $register` names each one',
        ),
      DoctorFinding(
        check: 'style',
        severity: DoctorSeverity.info,
        message: File(style).existsSync()
            ? 'style guide $style'
            : 'no $style; the guides alone shape entry bodies',
      ),
    ];
  }

  List<DoctorFinding> _skills(String directory, String command) {
    final findings = <DoctorFinding>[];
    final install = '`$command skills install $directory`';
    final known = {for (final guide in guides) guide.name};

    for (final guide in guides) {
      final path = p.join(directory, guide.name, 'SKILL.md');
      final finding = switch (_readSkill(path)) {
        _Missing() => DoctorFinding(
          check: 'skills',
          severity: DoctorSeverity.warn,
          message: 'no stub for guide ${guide.name} at $path',
          hint: install,
        ),
        _Unreadable(:final reason) => DoctorFinding(
          check: 'skills',
          severity: DoctorSeverity.warn,
          message: 'cannot read $path: $reason',
          hint: 'make it readable, or move it aside and run $install',
        ),
        _Skill(:final text) when !text.contains(skillStubMarker) =>
          DoctorFinding(
            check: 'skills',
            severity: DoctorSeverity.info,
            message: '$path is the adopter\'s own skill, not a decisions stub',
          ),
        _Skill(:final text) when text == skillStub(guide, command: command) =>
          DoctorFinding(
            check: 'skills',
            severity: DoctorSeverity.ok,
            message: '$path is current',
          ),
        _Skill() => DoctorFinding(
          check: 'skills',
          severity: DoctorSeverity.warn,
          message: '$path differs from the stub this binary writes',
          hint: '$install rewrites it, or upgrade decisions if it is newer',
        ),
      };
      findings.add(finding);
    }

    final List<Directory> others;
    try {
      others =
          (Directory(directory).existsSync()
                  ? Directory(directory).listSync()
                  : const <FileSystemEntity>[])
              .whereType<Directory>()
              .where((dir) => !known.contains(p.basename(dir.path)))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
    } on FileSystemException catch (error) {
      return findings..add(
        DoctorFinding(
          check: 'skills',
          severity: DoctorSeverity.warn,
          message: 'cannot list $directory: ${_reason(error)}',
          hint: 'make the skills directory readable',
        ),
      );
    }
    final adopters = <String>[];
    for (final dir in others) {
      final path = p.join(directory, p.basename(dir.path), 'SKILL.md');
      switch (_readSkill(path)) {
        case _Skill(:final text) when text.contains(skillStubMarker):
          final name = _stubName(text) ?? p.basename(dir.path);
          findings.add(
            known.contains(name)
                ? DoctorFinding(
                    check: 'skills',
                    severity: DoctorSeverity.warn,
                    message:
                        '$path is a stub for guide $name in a directory '
                        'install does not write',
                    hint:
                        'remove it; $install writes ${p.join(directory, name)}',
                  )
                : DoctorFinding(
                    check: 'skills',
                    severity: DoctorSeverity.fail,
                    message:
                        '$path points at guide $name, which this binary '
                        'does not carry',
                    hint: upgradeHint,
                  ),
          );
        case _Skill() || _Unreadable():
          adopters.add(p.basename(dir.path));
        case _Missing():
          break;
      }
    }
    if (adopters.isNotEmpty) {
      findings.add(
        DoctorFinding(
          check: 'skills',
          severity: DoctorSeverity.info,
          message:
              '${adopters.length} other skill${adopters.length == 1 ? '' : 's'} '
              'in $directory ${adopters.length == 1 ? 'is' : 'are'} the '
              'adopter\'s own: ${adopters.join(', ')}',
        ),
      );
    }
    return findings;
  }

  /// The `register.spec` an entry declares, or `null` when its front matter
  /// does not say; the parse check reports why.
  static int? _declaredSpec(String text) {
    final match = RegExp(
      r'^---\r?\n(.*?)\r?\n---\r?\n',
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;
    try {
      final Object? document = loadYaml(match.group(1)!);
      if (document is! YamlMap) return null;
      final Object? register = document['register'];
      if (register is! YamlMap) return null;
      final Object? spec = register['spec'];
      return spec is int ? spec : null;
    } on YamlException {
      return null;
    }
  }

  /// The guide name a stub's front matter declares.
  static String? _stubName(String text) =>
      RegExp(r'^name: (\S+)$', multiLine: true).firstMatch(text)?.group(1);

  static _SkillFile _readSkill(String path) =>
      switch (FileSystemEntity.typeSync(path)) {
        FileSystemEntityType.notFound => const _Missing(),
        FileSystemEntityType.file => _readFile(path),
        _ => const _Unreadable('not a file'),
      };

  static _SkillFile _readFile(String path) {
    try {
      return _Skill(File(path).readAsStringSync());
    } on FileSystemException catch (error) {
      return _Unreadable(_reason(error));
    }
  }

  static String _entries(int count) =>
      count == 1 ? '1 entry' : '$count entries';

  static String _reason(FileSystemException error) =>
      error.osError?.message ?? error.message;
}

/// What sits at a `SKILL.md` path.
sealed class _SkillFile {
  const _SkillFile();
}

final class _Missing extends _SkillFile {
  const _Missing();
}

final class _Unreadable extends _SkillFile {
  const _Unreadable(this.reason);

  final String reason;
}

final class _Skill extends _SkillFile {
  const _Skill(this.text);

  final String text;
}
