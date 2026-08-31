import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'lint.dart';

/// Composable `decisions` command group.
final class DecisionsCommand extends Command<int> {
  /// Creates the group with an injectable service and output sink.
  DecisionsCommand({DecisionLinter? linter, StringSink? output}) {
    addSubcommand(
      _LintCommand(
        linter: linter ?? const DecisionLintService(),
        output: output ?? stdout,
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
