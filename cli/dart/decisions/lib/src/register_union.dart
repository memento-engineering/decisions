import 'dart:io';

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
  /// Creates a snapshot over already-parsed [entries].
  ///
  /// The reading constructors infer [originRegister] from the register
  /// directory; this one takes it from a caller that already holds its
  /// entries, such as a roster assembled in memory.
  factory DecisionRegisterSnapshot({
    required String originRegister,
    required String originPath,
    required Iterable<DecisionEntry> entries,
  }) => DecisionRegisterSnapshot._(
    originRegister: originRegister,
    originPath: originPath,
    graph: DecisionGraph(entries),
  );

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
final class DecisionRegisterUnion implements DecisionRoster {
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
      final name = decisionOriginRegister(path);
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
  @override
  final List<DecisionRegisterSnapshot> registers;

  /// The same parsed registers, named for their snapshot role.
  List<DecisionRegisterSnapshot> get snapshots => registers;

  /// Entries that could not be parsed, in deterministic file/rule/message order.
  final List<DecisionLintDiagnostic> diagnostics;

  /// Finds the register named [originRegister], or returns null when absent.
  @override
  DecisionRegisterSnapshot? findRegister(String originRegister) {
    for (final register in registers) {
      if (register.originRegister == originRegister) return register;
    }
    return null;
  }
}

/// Sibling registers a verb resolves `<repo>#<slug>` citations against.
///
/// A roster is ADVISORY. A register missing from it means the citation cannot
/// be checked from here, not that it is wrong: a single checkout legitimately
/// sees one register while the graph spans several. Consumers therefore exempt
/// what they cannot see and check only what they can.
abstract interface class DecisionRoster {
  /// Registers in deterministic origin-register order.
  List<DecisionRegisterSnapshot> get registers;

  /// Finds the register named [originRegister], or returns null when absent.
  DecisionRegisterSnapshot? findRegister(String originRegister);
}

/// A roster read from register directories on disk.
final class DecisionRegisterRoster implements DecisionRoster {
  /// Creates the roster of a verb that can see no sibling register.
  const DecisionRegisterRoster.empty() : registers = const [];

  const DecisionRegisterRoster._(this.registers);

  /// Reads every directory in [registerPaths] that exists and parses.
  ///
  /// A path that is absent, malformed, or cannot form an unambiguous graph is
  /// skipped, and a name claimed by two paths resolves to neither: a roster
  /// never fails the verb that asked for it, and never resolves a citation it
  /// cannot resolve unambiguously.
  factory DecisionRegisterRoster.fromRegisterPaths(
    Iterable<String> registerPaths,
  ) {
    final byName = <String, DecisionRegisterSnapshot>{};
    final ambiguous = <String>{};
    for (final path in registerPaths) {
      final normalized = p.normalize(path);
      if (!Directory(normalized).existsSync()) continue;
      final String name;
      try {
        name = decisionOriginRegister(p.absolute(normalized));
      } on DecisionRegisterUnionException {
        continue;
      }
      if (byName.containsKey(name)) {
        ambiguous.add(name);
        continue;
      }
      try {
        byName[name] = DecisionRegisterSnapshot(
          originRegister: name,
          originPath: normalized,
          entries: readRegister(normalized, onParseError: (_) {}),
        );
      } on DecisionParseException {
        continue;
      } on DecisionGraphException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    byName.removeWhere((name, _) => ambiguous.contains(name));
    final registers = byName.values.toList()
      ..sort(
        (left, right) => left.originRegister.compareTo(right.originRegister),
      );
    return DecisionRegisterRoster._(
      List<DecisionRegisterSnapshot>.unmodifiable(registers),
    );
  }

  @override
  final List<DecisionRegisterSnapshot> registers;

  @override
  DecisionRegisterSnapshot? findRegister(String originRegister) {
    for (final register in registers) {
      if (register.originRegister == originRegister) return register;
    }
    return null;
  }
}

/// A `<register>#<reference>` citation, split into its two halves.
final class DecisionReference {
  /// Creates a qualified citation.
  const DecisionReference({required this.register, required this.reference});

  /// Splits [value] at its first `#`.
  ///
  /// Returns null when [value] carries no `#` at all, and also when either
  /// half is empty — an unusable qualified citation resolves to nothing.
  static DecisionReference? parse(String value) {
    final separator = value.indexOf('#');
    if (separator <= 0 || separator == value.length - 1) return null;
    return DecisionReference(
      register: value.substring(0, separator),
      reference: value.substring(separator + 1),
    );
  }

  /// Whether [value] is qualified at all, well-formed or not.
  static bool isQualified(String value) => value.contains('#');

  /// The origin register named before the `#`.
  final String register;

  /// The slug or legacy id named after the `#`.
  final String reference;

  @override
  String toString() => '$register#$reference';
}

/// Cross-register edge resolution over any [DecisionRoster].
extension DecisionRosterEdges on DecisionRoster {
  /// Resolves [reference] to its entry, or null when the named register is
  /// absent from this roster or holds no such slug or legacy id.
  DecisionEntry? resolveReference(DecisionReference reference) =>
      findRegister(reference.register)?.graph.findEntry(reference.reference);

  /// Qualified references to entries elsewhere in the roster whose authored
  /// [kind] edge targets [target] in [originRegister], sorted.
  ///
  /// Registers named [originRegister] are skipped: that register's own edges
  /// resolve locally, and the roster may hold a staler copy of it.
  List<String> crossRegisterSourcesOf({
    required String originRegister,
    required DecisionEntry target,
    required DecisionEdgeKind kind,
  }) {
    final handles = <String>{
      '$originRegister#${target.slug}',
      if (target.legacyId case final legacyId?) '$originRegister#$legacyId',
    };
    final sources = <String>[];
    for (final register in registers) {
      if (register.originRegister == originRegister) continue;
      for (final entry in register.graph.entries.values) {
        final authored = switch (kind) {
          DecisionEdgeKind.obsoletes => entry.obsoletes,
          DecisionEdgeKind.updates => entry.updates,
        };
        if (authored.any(handles.contains)) {
          sources.add('${register.originRegister}#${entry.slug}');
        }
      }
    }
    return sources..sort();
  }

  /// Qualified values in [cached] this roster cannot resolve, sorted.
  ///
  /// A cached back-edge into a register the roster does not carry is exempt
  /// rather than stale: the checkout simply cannot see the other side.
  List<String> unresolvableCached(Iterable<String> cached) {
    final unresolvable = <String>[];
    for (final value in cached) {
      if (!DecisionReference.isQualified(value)) continue;
      final reference = DecisionReference.parse(value);
      if (reference == null) continue;
      if (findRegister(reference.register) != null) continue;
      unresolvable.add(value);
    }
    return unresolvable..sort();
  }
}

/// The force-cache references [target] must carry for one edge [kind].
///
/// A local source contributes its slug. A roster source in another register
/// contributes `<repo>#<slug>`. A qualified value already in [cached] whose
/// register is absent from [roster] is carried through unchanged: this
/// checkout cannot see the other side, so the value is exempt rather than
/// stale. The result is sorted, and is what `decisions lint` checks the
/// cache against and what a force mutation writes.
List<String> expectedForceCache({
  required DecisionRoster roster,
  required String? originRegister,
  required DecisionEntry target,
  required Iterable<DecisionEntry> localSources,
  required Iterable<String> cached,
  required DecisionEdgeKind kind,
}) => <String>[
  for (final source in localSources) source.slug,
  if (originRegister != null)
    ...roster.crossRegisterSourcesOf(
      originRegister: originRegister,
      target: target,
      kind: kind,
    ),
  ...roster.unresolvableCached(cached),
]..sort();

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

/// Infers the cross-register namespace a register directory publishes under.
///
/// `<repo>/docs/decisions` names `<repo>`, and a provisioned grid worktree
/// under `<repo>/.grid/worktrees/<substation>/<bead>/docs/decisions` names the
/// substation rather than the bead.
String decisionOriginRegister(String registerPath) {
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
