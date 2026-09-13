import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'index_command.dart';
import 'legacy.dart';
import 'lint.dart';
import 'mutation.dart';
import 'register_union.dart';
import 'search_command.dart';

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
    final resolvedOutput = output ?? stdout;
    final resolvedError = error ?? stderr;
    final resolvedRegisterPaths =
        registerPaths ?? () => const <String>['docs/decisions'];
    addSubcommand(
      IndexCommand(
        output: resolvedOutput,
        registerPaths: resolvedRegisterPaths,
      ),
    );
    addSubcommand(
      DecisionSearchCommand(
        registerPaths: resolvedRegisterPaths,
        output: resolvedOutput,
        error: resolvedError,
      ),
    );
    addSubcommand(
      _LintCommand(
        linter: linter,
        registerPaths: resolvedRegisterPaths,
        output: resolvedOutput,
      ),
    );
    addSubcommand(
      _MigrateLegacyCommand(
        converter: legacyConverter ?? const LegacyRegisterConversionService(),
        output: resolvedOutput,
      ),
    );
    for (final verb in _ForceVerb.values) {
      addSubcommand(
        _MutationCommand(
          verb: verb,
          mutator: mutator,
          linter: linter,
          registerPaths: resolvedRegisterPaths,
          output: resolvedOutput,
        ),
      );
    }
  }

  @override
  String get name => 'decisions';

  @override
  String get description => 'Inspect and maintain a decision register.';
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

  /// The verb's one-line command description.
  String get description => switch (this) {
    _ForceVerb.obsolete => 'Mark a decision as entirely replaced.',
    _ForceVerb.update => 'Record an amendment to an accepted decision.',
    _ForceVerb.vacate => 'Withdraw a decision after recording a successor.',
  };
}

final class _MutationCommand extends Command<int> {
  _MutationCommand({
    required _ForceVerb verb,
    required DecisionMutator? mutator,
    required DecisionLinter? linter,
    required RegisterPathResolver registerPaths,
    required StringSink output,
  }) : _verb = verb,
       _mutator = mutator,
       _linter = linter,
       _registerPaths = registerPaths,
       _output = output {
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

  @override
  String get name => _verb.name;

  @override
  String get description => _verb.description;

  @override
  int run() {
    final positional = argResults!.rest;
    if (positional.length != 1) {
      _output.writeln('error: expected exactly one target slug');
      return 1;
    }
    final successor = argResults!.option(_verb.successorOption);
    if (successor == null || successor.isEmpty) {
      _output.writeln(
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
      _output.writeln('error: ${error.message}');
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
