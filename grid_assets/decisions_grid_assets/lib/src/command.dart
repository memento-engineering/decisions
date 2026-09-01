import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;

/// Reads the roots of the substations mounted by a resident station.
typedef MountedSubstationRoots = Iterable<String> Function();

/// Tests whether a resolved decision-register directory exists.
typedef RegisterDirectoryExists = bool Function(String path);

bool _directoryExists(String path) => Directory(path).existsSync();

/// Builds the composable `decisions` command group for a station runner.
///
/// The station provides [mountedSubstationRoots] from its resident tree. Each
/// `decisions index` run reads that callback afresh, selects existing
/// `docs/decisions` directories, and delegates the union to the agnostic
/// decisions engine.
DecisionsCommand buildDecisionsCommand({
  required MountedSubstationRoots mountedSubstationRoots,
  RegisterDirectoryExists? registerExists,
  DecisionLinter? linter,
  StringSink? output,
}) {
  final exists = registerExists ?? _directoryExists;
  final command = DecisionsCommand(linter: linter, output: output);
  command.addSubcommand(
    IndexCommand(
      output: output,
      registerPaths: () sync* {
        for (final root in mountedSubstationRoots()) {
          final registerPath = p.normalize(p.join(root, 'docs', 'decisions'));
          if (exists(registerPath)) yield registerPath;
        }
      },
    ),
  );
  return command;
}
