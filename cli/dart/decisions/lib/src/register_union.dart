import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'entry.dart';
import 'graph.dart';
import 'lint.dart';

/// Lowest decision-entry spec this artifact reads.
const decisionEntrySpecMinimum = 1;

/// Highest decision-entry spec this artifact reads.
const decisionEntrySpecMaximum = 1;

/// One parsed register inside a [DecisionRegisterUnion].
final class DecisionRegisterSnapshot {
  const DecisionRegisterSnapshot._({
    required this.originRegister,
    required this.originPath,
    required this.graph,
  });

  /// Cross-register namespace inferred from the register path.
  final String originRegister;

  /// Alias for [originRegister] when treating the snapshot as a register.
  String get name => originRegister;

  /// Normalized register-directory path supplied by the caller.
  final String originPath;

  /// Alias for [originPath] when treating the snapshot as a register.
  String get path => originPath;

  /// Parsed, immutable graph for this register.
  final DecisionGraph graph;
}

/// A parsed, deterministic union shared by register readers.
final class DecisionRegisterUnion {
  DecisionRegisterUnion._({
    required List<DecisionRegisterSnapshot> registers,
    required List<DecisionLintDiagnostic> diagnostics,
  }) : registers = List<DecisionRegisterSnapshot>.unmodifiable(registers),
       diagnostics = List<DecisionLintDiagnostic>.unmodifiable(diagnostics);

  /// Reads [registerPaths], retaining malformed-entry diagnostics while
  /// refusing inputs that cannot form a supported, unambiguous union.
  factory DecisionRegisterUnion.fromRegisterPaths(
    Iterable<String> registerPaths,
  ) {
    final paths = registerPaths.map(p.normalize).toList(growable: false);
    if (paths.isEmpty) {
      throw const DecisionRegisterUnionException(
        'at least one register directory is required',
      );
    }

    final diagnostics = <DecisionLintDiagnostic>[];
    final registersByName = <String, DecisionRegisterSnapshot>{};
    for (final path in paths) {
      final name = _originRegister(path);
      final previous = registersByName[name];
      if (previous != null) {
        throw DecisionRegisterUnionException(
          'duplicate origin register "$name" for '
          '"${previous.originPath}" and "$path"',
        );
      }

      final entries = readRegister(
        path,
        onParseError: (error) {
          diagnostics.add(DecisionLintDiagnostic.fromParseException(error));
        },
      );
      for (final entry in entries) {
        if (entry.spec < decisionEntrySpecMinimum ||
            entry.spec > decisionEntrySpecMaximum) {
          throw DecisionRegisterUnionException(
            '"${entry.file}" declares unsupported decision spec ${entry.spec}; '
            'supported range is $decisionEntrySpecMinimum through '
            '$decisionEntrySpecMaximum',
          );
        }
      }
      registersByName[name] = DecisionRegisterSnapshot._(
        originRegister: name,
        originPath: path,
        graph: DecisionGraph(entries),
      );
    }

    final registers = registersByName.values.toList(growable: false)
      ..sort(
        (left, right) => left.originRegister.compareTo(right.originRegister),
      );
    diagnostics.sort(DecisionLintDiagnostic.compare);
    return DecisionRegisterUnion._(
      registers: registers,
      diagnostics: diagnostics,
    );
  }

  /// Parsed registers in deterministic origin-register order.
  final List<DecisionRegisterSnapshot> registers;

  /// The same parsed registers, named for their snapshot role.
  List<DecisionRegisterSnapshot> get snapshots => registers;

  /// Entries that could not be parsed, in deterministic file/rule/message order.
  final List<DecisionLintDiagnostic> diagnostics;

  /// Finds the register named [originRegister], or returns null when absent.
  DecisionRegisterSnapshot? findRegister(String originRegister) {
    for (final register in registers) {
      if (register.originRegister == originRegister) return register;
    }
    return null;
  }
}

/// Whether [surfaces] govern [rosterRelativePath] for [originRegister].
///
/// A surface beginning with `*/` is already roster-qualified as a wildcard.
/// Every other authored surface is qualified with its origin register.
bool matchesDecisionSurface({
  required String originRegister,
  required Iterable<String> surfaces,
  required String rosterRelativePath,
}) {
  final normalized = p.posix.normalize(
    rosterRelativePath.replaceAll('\\', '/'),
  );
  return surfaces.any((surface) {
    final normalizedSurface = surface.replaceAll('\\', '/');
    final pattern = normalizedSurface.startsWith('*/')
        ? normalizedSurface
        : '$originRegister/$normalizedSurface';
    return Glob(pattern, context: p.posix).matches(normalized);
  });
}

/// Thrown when register inputs cannot form a deterministic shared union.
class DecisionRegisterUnionException implements Exception {
  /// Creates a union exception with [message].
  const DecisionRegisterUnionException(this.message);

  /// What prevented union construction.
  final String message;

  @override
  String toString() => 'DecisionRegisterUnionException: $message';
}

String _originRegister(String registerPath) {
  final parts = p.split(p.normalize(registerPath));
  if (parts.length >= 3 &&
      parts.last == 'decisions' &&
      parts[parts.length - 2] == 'docs') {
    if (parts.length >= 6 &&
        parts[parts.length - 6] == '.grid' &&
        parts[parts.length - 5] == 'worktrees') {
      return parts[parts.length - 4];
    }
    return parts[parts.length - 3];
  }
  final name = p.basename(p.normalize(registerPath));
  if (name.isEmpty || name == p.separator) {
    throw DecisionRegisterUnionException(
      'cannot infer an origin register from "$registerPath"',
    );
  }
  return name;
}
