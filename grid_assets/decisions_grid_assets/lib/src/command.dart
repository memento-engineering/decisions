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
/// `decisions index` or `decisions search` run reads that callback afresh,
/// selects existing `docs/decisions` directories, and delegates the union to
/// the agnostic decisions engine.
///
/// [slugLimits] supplies each register's slug limit, keyed by the register
/// name a mounted substation publishes under (the `<repo>` of
/// `<repo>#<slug>`); a register it does not name applies its fallback,
/// [defaultMaxSlugLength] by default. An explicit `--max-slug-length` on a run
/// wins.
DecisionsCommand buildDecisionsCommand({
  required MountedSubstationRoots mountedSubstationRoots,
  RegisterDirectoryExists? registerExists,
  DecisionLinter? linter,
  DecisionSlugLimits slugLimits = const DecisionSlugLimits(),
  StringSink? output,
  StringSink? error,
}) {
  final exists = registerExists ?? _directoryExists;
  Iterable<String> registerPaths() sync* {
    for (final root in mountedSubstationRoots()) {
      final registerPath = p.normalize(p.join(root, 'docs', 'decisions'));
      if (exists(registerPath)) yield registerPath;
    }
  }

  return DecisionsCommand(
    linter: linter,
    registerPaths: registerPaths,
    slugLimits: slugLimits,
    output: output,
    error: error,
  );
}
