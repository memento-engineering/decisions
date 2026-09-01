import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'legacy.dart';
import 'lint.dart';

/// Composable `decisions` command group.
final class DecisionsCommand extends Command<int> {
  /// Creates the group with injectable services and output sink.
  DecisionsCommand({
    DecisionLinter? linter,
    LegacyRegisterConverter? legacyConverter,
    StringSink? output,
  }) {
    final sink = output ?? stdout;
    addSubcommand(
      _LintCommand(linter: linter ?? const DecisionLintService(), output: sink),
    );
    addSubcommand(
      _MigrateLegacyCommand(
        converter: legacyConverter ?? const LegacyRegisterConversionService(),
        output: sink,
      ),
    );
  }

  @override
  String get name => 'decisions';

  @override
  String get description => 'Inspect and maintain a decision register.';
}

final class _LintCommand extends Command<int> {
  _LintCommand({required DecisionLinter linter, required StringSink output})
    : _linter = linter,
      _output = output {
    argParser
      ..addOption(
        'repo-root',
        defaultsTo: '.',
        help: 'Repository root used to resolve governed surfaces.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit the schema-versioned JSON result.',
      );
  }

  final DecisionLinter _linter;
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
    final result = _linter.lint(
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
