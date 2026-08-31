import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'index.dart';

/// Emits a structured decision index over explicit register directories.
final class IndexCommand extends Command<int> {
  /// Creates the command, writing JSON to [output] or standard output.
  IndexCommand({StringSink? output}) : _output = output ?? stdout {
    argParser.addOption(
      'surface',
      abbr: 's',
      valueHelp: 'register/path',
      help: 'Keep only decisions governing this roster-qualified path.',
    );
  }

  final StringSink _output;

  @override
  String get name => 'index';

  @override
  String get description =>
      'Index one or more explicit decision-register directories as JSON.';

  @override
  FutureOr<int> run() {
    final results = argResults!;
    final registerPaths = results.rest;
    if (registerPaths.isEmpty) {
      usageException('at least one register directory is required');
    }

    final surface = results.option('surface');
    final union = DecisionIndex.fromRegisterPaths(registerPaths);
    final index = surface == null ? union : union.governing(surface);
    _output.writeln(jsonEncode(index.toJson()));
    return 0;
  }
}
