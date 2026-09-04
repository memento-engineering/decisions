import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'index.dart';

/// Resolves decision-register directories at command run time.
typedef RegisterPathResolver = Iterable<String> Function();

/// Emits a structured decision index over explicit or resolved registers.
final class IndexCommand extends Command<int> {
  /// Creates the command, writing JSON to [output] or standard output.
  ///
  /// Explicit positional paths win. When argv carries none, [registerPaths]
  /// is invoked at run time; omitting it preserves the tier-1 zero-path
  /// refusal.
  IndexCommand({StringSink? output, RegisterPathResolver? registerPaths})
    : _output = output ?? stdout,
      _registerPaths = registerPaths {
    argParser
      ..addOption(
        'surface',
        abbr: 's',
        valueHelp: 'register/path',
        help: 'Keep only decisions governing this roster-qualified path.',
      )
      ..addFlag(
        'human',
        negatable: false,
        help: 'Emit a human-readable decision and diagnostic summary.',
      );
  }

  final StringSink _output;
  final RegisterPathResolver? _registerPaths;

  @override
  String get name => 'index';

  @override
  String get description =>
      'Index one or more decision-register directories as JSON.';

  @override
  FutureOr<int> run() {
    final results = argResults!;
    final explicitPaths = results.rest;
    final registerPaths = explicitPaths.isNotEmpty
        ? explicitPaths
        : _registerPaths?.call().toList(growable: false) ?? const <String>[];
    if (registerPaths.isEmpty) {
      usageException('at least one register directory is required');
    }

    final surface = results.option('surface');
    final union = DecisionIndex.fromRegisterPaths(registerPaths);
    final index = surface == null ? union : union.governing(surface);
    if (results.flag('human')) {
      _writeHuman(index);
    } else {
      _output.writeln(jsonEncode(index.toJson()));
    }
    return 0;
  }

  void _writeHuman(DecisionIndex index) {
    _output.writeln('decisions: ${index.decisions.length}');
    for (final decision in index.decisions) {
      _output.writeln(
        '- ${decision.originRegister}#${decision.slug} [${decision.status}]',
      );
    }
    _output.writeln('diagnostics: ${index.diagnostics.length}');
    for (final diagnostic in index.diagnostics) {
      _output.writeln(
        '- ${diagnostic.file}: [${diagnostic.ruleId}] ${diagnostic.message}',
      );
    }
  }
}
