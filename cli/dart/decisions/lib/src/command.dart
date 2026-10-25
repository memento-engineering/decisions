import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'doctor_command.dart';
import 'index_command.dart';
import 'instructions_command.dart';
import 'legacy.dart';
import 'lint.dart';
import 'mutation.dart';
import 'new_command.dart';
import 'register_union.dart';
import 'search_command.dart';
import 'version.dart';

/// Composable `decisions` command group.
final class DecisionsCommand extends Command<int> {
  /// Creates the group with injectable services, register resolver, and sinks.
  DecisionsCommand({
    DecisionLinter? linter,
    LegacyRegisterConverter? legacyConverter,
    DecisionMutator? mutator,
    RegisterPathResolver? registerPaths,
    StringSink? output,
    StringSink? error,
  }) {
    _verbs(
      linter: linter,
      legacyConverter: legacyConverter,
      mutator: mutator,
      registerPaths: registerPaths,
      output: output,
      error: error,
    ).forEach(addSubcommand);
  }

  @override
  String get name => 'decisions';

  @override
  String get description => 'Inspect and maintain a decision register.';
}

/// The standalone `decisions` executable: the same verbs as
/// [DecisionsCommand], at top level, plus `--version`.
///
/// [run] never throws a [UsageException]; it reports one on the error sink and
/// returns [usageExitCode].
final class DecisionsCommandRunner extends CommandRunner<int> {
  /// Creates the runner with injectable services, register resolver, and sinks.
  DecisionsCommandRunner({
    DecisionLinter? linter,
    LegacyRegisterConverter? legacyConverter,
    DecisionMutator? mutator,
    RegisterPathResolver? registerPaths,
    StringSink? output,
    StringSink? error,
  }) : _output = output ?? stdout,
       _error = error ?? stderr,
       super('decisions', 'Inspect and maintain a decision register.') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the artifact version and the spec it reads and writes.',
    );
    _verbs(
      linter: linter,
      legacyConverter: legacyConverter,
      mutator: mutator,
      registerPaths: registerPaths,
      output: _output,
      error: _error,
    ).forEach(addCommand);
  }

  /// The exit code for a malformed invocation (`EX_USAGE`).
  static const usageExitCode = 64;

  final StringSink _output;
  final StringSink _error;

  /// The `--version` line: the artifact version, then the spec range it
  /// reads and the one spec it writes (`spec-and-artifact-versioning`).
  static String get versionLine =>
      'decisions $decisionsVersion '
      '(reads spec <= ${DecisionLintService.supportedSpec}, '
      'writes spec ${DecisionLintService.supportedSpec})';

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      return await super.run(args) ?? 0;
    } on UsageException catch (error) {
      _error
        ..writeln(error.message)
        ..writeln()
        ..writeln(error.usage);
      return usageExitCode;
    }
  }

  @override
  void printUsage() => _output.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      _output.writeln(versionLine);
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}

/// Every verb, built once per host so both hosts share one wiring.
List<Command<int>> _verbs({
  required DecisionLinter? linter,
  required LegacyRegisterConverter? legacyConverter,
  required DecisionMutator? mutator,
  required RegisterPathResolver? registerPaths,
  required StringSink? output,
  required StringSink? error,
}) {
  final resolvedOutput = output ?? stdout;
  final resolvedError = error ?? stderr;
  final resolvedRegisterPaths =
      registerPaths ?? () => const <String>['docs/decisions'];
  return [
    IndexCommand(output: resolvedOutput, registerPaths: resolvedRegisterPaths),
    DecisionSearchCommand(
      registerPaths: resolvedRegisterPaths,
      output: resolvedOutput,
      error: resolvedError,
    ),
    _LintCommand(
      linter: linter,
      registerPaths: resolvedRegisterPaths,
      output: resolvedOutput,
    ),
    DoctorCommand(output: resolvedOutput),
    _MigrateLegacyCommand(
      converter: legacyConverter ?? const LegacyRegisterConversionService(),
      output: resolvedOutput,
    ),
    DecisionNewCommand(
      linter: linter,
      registerPaths: resolvedRegisterPaths,
      output: resolvedOutput,
      error: resolvedError,
    ),
    for (final verb in _ForceVerb.values)
      _MutationCommand(
        verb: verb,
        mutator: mutator,
        linter: linter,
        registerPaths: resolvedRegisterPaths,
        output: resolvedOutput,
        error: resolvedError,
      ),
    PrimeCommand(output: resolvedOutput),
    GuideCommand(output: resolvedOutput),
    SkillsCommand(output: resolvedOutput, error: resolvedError),
  ];
}

final class _LintCommand extends Command<int> {
  _LintCommand({
    required DecisionLinter? linter,
    required RegisterPathResolver registerPaths,
    required StringSink output,
  }) : _linter = linter,
       _registerPaths = registerPaths,
       _output = output {
    argParser
      ..addOption(
        'repo-root',
        defaultsTo: '.',
        help: 'Repository root used to resolve governed surfaces.',
      )
      ..addMultiOption('roster', valueHelp: 'register-path', help: _rosterHelp)
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the schema-versioned JSON result.',
      );
  }

  final DecisionLinter? _linter;
  final RegisterPathResolver _registerPaths;
  final StringSink _output;

  @override
  String get name => 'lint';

  @override
  String get description => 'Validate one decision register and its graph.';

  @override
  int run() {
    final positional = argResults!.rest;
    if (positional.length != 1) {
      usageException('Expected exactly one register path.');
    }
    final linter =
        _linter ??
        DecisionLintService(
          roster: _resolveRoster(argResults!, _registerPaths),
        );
    final result = linter.lint(
      registerPath: positional.single,
      repoRoot: argResults!.option('repo-root')!,
    );
    if (argResults!.flag('json')) {
      _output.writeln(jsonEncode(result.toJson()));
    } else if (result.isClean) {
      _output.writeln('${result.register}: clean');
    } else {
      for (final diagnostic in result.diagnostics) {
        _output.writeln(
          '${diagnostic.file}: [${diagnostic.ruleId}] '
          '${diagnostic.message}',
        );
      }
    }
    return result.isClean ? 0 : 1;
  }
}

final class _MigrateLegacyCommand extends Command<int> {
  _MigrateLegacyCommand({
    required LegacyRegisterConverter converter,
    required StringSink output,
  }) : _converter = converter,
       _output = output {
    argParser
      ..addMultiOption(
        'surface',
        abbr: 's',
        valueHelp: 'glob',
        help: 'Authored surface copied unchanged to every converted entry.',
      )
      ..addOption(
        'human',
        mandatory: true,
        valueHelp: 'name',
        help: 'Sole decision-maker for explicitly ratified ADRs.',
      )
      ..addMultiOption(
        'ratified',
        valueHelp: 'YYYY-MM-DD=path',
        help: 'Ratified ADR converted whole; repeat for each selected file.',
      );
  }

  final LegacyRegisterConverter _converter;
  final StringSink _output;

  @override
  String get name => 'migrate-legacy';

  @override
  String get description =>
      'Convert one ADR-0000 register and explicit ratified ADRs.';

  @override
  int run() {
    final positional = argResults!.rest;
    if (positional.length != 2) {
      usageException('Expected REGISTER_FILE and OUTPUT_DIRECTORY.');
    }
    final surfaces = argResults!.multiOption('surface');
    if (surfaces.isEmpty) {
      usageException('At least one --surface is required.');
    }
    final ratified = argResults!
        .multiOption('ratified')
        .map(_parseRatified)
        .toList(growable: false);
    final result = _converter.convert(
      registerFile: positional[0],
      ratifiedAdrs: ratified,
      surfaces: surfaces,
      human: argResults!.option('human')!,
      outputDirectory: positional[1],
    );
    _output.writeln('converted ${result.files.length} decision entries');
    return 0;
  }

  LegacyRatifiedAdr _parseRatified(String value) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})=(.+)$').firstMatch(value);
    if (match == null) {
      usageException('--ratified must use the exact YYYY-MM-DD=path form');
    }
    return LegacyRatifiedAdr(file: match.group(2)!, date: match.group(1)!);
  }
}

/// The three permitted decision-force operations, as command verbs.
enum _ForceVerb {
  /// Mark a decision as entirely replaced.
  obsolete(successorOption: 'by'),

  /// Record an amendment to an accepted decision.
  update(successorOption: 'by'),

  /// Withdraw a decision after recording a successor.
  vacate(successorOption: 'successor');

  const _ForceVerb({required this.successorOption});

  /// The option naming this verb's successor on the command line.
  final String successorOption;

  /// The verb's one-line summary, as `decisions help` lists it.
  String get summary => switch (this) {
    _ForceVerb.obsolete => 'Mark a decision as entirely replaced.',
    _ForceVerb.update => 'Record an amendment to an accepted decision.',
    _ForceVerb.vacate => 'Withdraw a decision after recording a successor.',
  };

  /// The verb's `--help` description: the [summary], then its contract.
  String get description =>
      '$summary\n'
      '\n'
      'Exits 0 when the target\'s cache is written, printing '
      '"$name <slug>: clean"\non stdout. Exits 1 when refused, having '
      'written nothing, with the reason on stderr.';
}

final class _MutationCommand extends Command<int> {
  _MutationCommand({
    required _ForceVerb verb,
    required DecisionMutator? mutator,
    required DecisionLinter? linter,
    required RegisterPathResolver registerPaths,
    required StringSink output,
    required StringSink error,
  }) : _verb = verb,
       _mutator = mutator,
       _linter = linter,
       _registerPaths = registerPaths,
       _output = output,
       _error = error {
    argParser
      ..addOption(
        verb.successorOption,
        valueHelp: 'slug',
        help:
            'The already-recorded successor decision, as a local slug or '
            '<repo>#<slug>.',
      )
      ..addOption(
        'register',
        defaultsTo: 'docs/decisions',
        help: 'Decision register containing the target entry.',
      )
      ..addOption(
        'repo-root',
        defaultsTo: '.',
        help: 'Repository root used for candidate linting.',
      )
      ..addMultiOption('roster', valueHelp: 'register-path', help: _rosterHelp);
  }

  final _ForceVerb _verb;
  final DecisionMutator? _mutator;
  final DecisionLinter? _linter;
  final RegisterPathResolver _registerPaths;
  final StringSink _output;
  final StringSink _error;

  @override
  String get name => _verb.name;

  @override
  String get description => _verb.description;

  @override
  void printUsage() => _output.writeln(usage);

  @override
  int run() {
    final positional = argResults!.rest;
    if (positional.length != 1) {
      _error.writeln('error: expected exactly one target slug');
      return 1;
    }
    final successor = argResults!.option(_verb.successorOption);
    if (successor == null || successor.isEmpty) {
      _error.writeln(
        'error: --${_verb.successorOption} requires a successor slug',
      );
      return 1;
    }

    final mutator =
        _mutator ??
        DecisionMutationService(
          linter: _linter,
          roster: _resolveRoster(argResults!, _registerPaths),
        );
    final run = switch (_verb) {
      _ForceVerb.obsolete => mutator.obsolete,
      _ForceVerb.update => mutator.update,
      _ForceVerb.vacate => mutator.vacate,
    };

    try {
      run(
        registerPath: argResults!.option('register')!,
        repoRoot: argResults!.option('repo-root')!,
        target: positional.single,
        successor: successor,
      );
      _output.writeln('$name ${positional.single}: clean');
      return 0;
    } on DecisionMutationException catch (error) {
      _error.writeln('error: ${error.message}');
      return 1;
    }
  }
}

const _rosterHelp =
    'Sibling decision register resolved for <repo>#<slug> edges; repeatable. '
    'Defaults to the composed register resolver.';

/// The roster a verb resolves cross-register references against.
///
/// Explicit `--roster` paths win; otherwise the composed resolver is read
/// afresh, so a station sees the registers its roster mounts right now.
DecisionRoster _resolveRoster(
  ArgResults results,
  RegisterPathResolver registerPaths,
) {
  final explicit = results.multiOption('roster');
  return DecisionRegisterRoster.fromRegisterPaths(
    explicit.isNotEmpty ? explicit : registerPaths(),
  );
}
