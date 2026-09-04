import 'package:glob/glob.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import 'entry.dart';
import 'graph.dart';
import 'lint.dart';

part 'index.g.dart';

/// Lowest decision-entry spec this artifact reads.
const decisionEntrySpecMinimum = 1;

/// Highest decision-entry spec this artifact reads.
const decisionEntrySpecMaximum = 1;

/// JSON schema version emitted by [DecisionIndex.toJson].
const decisionIndexOutputSpec = 2;

/// Whether an authored index edge found its target in the supplied union.
enum DecisionIndexEdgeResolution {
  /// The target register and decision are both present.
  resolved,

  /// The target register or decision is absent.
  dangling,
}

/// One authored edge in index output.
@JsonSerializable(createFactory: false)
final class IndexedDecisionEdge {
  /// Creates an output edge.
  const IndexedDecisionEdge({
    required this.kind,
    required this.reference,
    required this.resolution,
    this.targetRegister,
    this.targetSlug,
  });

  /// Whether the authored relation obsoletes or updates its target.
  final DecisionEdgeKind kind;

  /// The target spelling authored in the source entry.
  final String reference;

  /// Whether the target resolved inside this union.
  final DecisionIndexEdgeResolution resolution;

  /// Canonical target register when resolved.
  @JsonKey(includeIfNull: false)
  final String? targetRegister;

  /// Canonical target slug when resolved, even when [reference] used a legacy id.
  @JsonKey(includeIfNull: false)
  final String? targetSlug;

  /// Converts this edge to the documented JSON shape.
  Map<String, dynamic> toJson() => _$IndexedDecisionEdgeToJson(this);
}

/// One decision in index output.
@JsonSerializable(createFactory: false, explicitToJson: true)
final class IndexedDecision {
  /// Creates an indexed decision.
  IndexedDecision({
    required this.originRegister,
    required this.originPath,
    required this.slug,
    required this.status,
    required List<String> surfaces,
    required List<IndexedDecisionEdge> edges,
  }) : surfaces = List<String>.unmodifiable(surfaces),
       edges = List<IndexedDecisionEdge>.unmodifiable(edges);

  /// Cross-register namespace inferred from the register path.
  final String originRegister;

  /// Normalized register-directory path supplied by the caller.
  final String originPath;

  /// Canonical authored decision slug.
  final String slug;

  /// Cached MADR status read from the entry without mutation.
  final String status;

  /// Authored surface globs.
  final List<String> surfaces;

  /// Authored outgoing edges with union resolution state.
  final List<IndexedDecisionEdge> edges;

  /// Converts this decision to the documented JSON shape.
  Map<String, dynamic> toJson() => _$IndexedDecisionToJson(this);
}

/// A deterministic, read-only union over one or more decision registers.
@JsonSerializable(createFactory: false, explicitToJson: true)
final class DecisionIndex {
  DecisionIndex._({
    required List<IndexedDecision> decisions,
    required List<DecisionLintDiagnostic> diagnostics,
  }) : spec = decisionIndexOutputSpec,
       decisions = List<IndexedDecision>.unmodifiable(decisions),
       diagnostics = List<DecisionLintDiagnostic>.unmodifiable(diagnostics);

  /// Reads [registerPaths] and resolves their authored graphs into one union.
  factory DecisionIndex.fromRegisterPaths(Iterable<String> registerPaths) {
    final paths = registerPaths.map(p.normalize).toList(growable: false);
    if (paths.isEmpty) {
      throw const DecisionIndexException(
        'at least one register directory is required',
      );
    }

    final diagnostics = <DecisionLintDiagnostic>[];
    final registers = <String, _LoadedRegister>{};
    for (final path in paths) {
      final name = _originRegister(path);
      final previous = registers[name];
      if (previous != null) {
        throw DecisionIndexException(
          'duplicate origin register "$name" for '
          '"${previous.path}" and "$path"',
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
          throw DecisionIndexException(
            '"${entry.file}" declares unsupported decision spec ${entry.spec}; '
            'supported range is $decisionEntrySpecMinimum through '
            '$decisionEntrySpecMaximum',
          );
        }
      }
      registers[name] = _LoadedRegister(
        name: name,
        path: path,
        graph: DecisionGraph(entries),
      );
    }

    final decisions = <IndexedDecision>[];
    for (final register in registers.values) {
      for (final entry in register.graph.entries.values) {
        final edges = <IndexedDecisionEdge>[
          for (final edge in register.graph.outgoingFrom(entry.slug))
            IndexedDecisionEdge(
              kind: edge.kind,
              reference: edge.targetReference,
              resolution: DecisionIndexEdgeResolution.resolved,
              targetRegister: register.name,
              targetSlug: edge.target.slug,
            ),
          for (final edge in register.graph.pendingFrom(entry.slug))
            _resolvePending(edge, registers),
        ]..sort(_compareEdges);

        decisions.add(
          IndexedDecision(
            originRegister: register.name,
            originPath: register.path,
            slug: entry.slug,
            status: entry.status,
            surfaces: entry.surfaces,
            edges: edges,
          ),
        );
      }
    }
    decisions.sort((left, right) {
      final registerOrder = left.originRegister.compareTo(right.originRegister);
      return registerOrder != 0
          ? registerOrder
          : left.slug.compareTo(right.slug);
    });
    diagnostics.sort(DecisionLintDiagnostic.compare);
    return DecisionIndex._(decisions: decisions, diagnostics: diagnostics);
  }

  /// Output schema version.
  final int spec;

  /// All decisions in deterministic origin-register/slug order.
  final List<IndexedDecision> decisions;

  /// Entries that could not be parsed, in deterministic file/rule/message order.
  final List<DecisionLintDiagnostic> diagnostics;

  /// Returns only decisions governing [rosterRelativePath].
  DecisionIndex governing(String rosterRelativePath) {
    final normalized = p.posix.normalize(
      rosterRelativePath.replaceAll('\\', '/'),
    );
    return DecisionIndex._(
      decisions: decisions
          .where((decision) {
            return decision.surfaces.any((surface) {
              final normalizedSurface = surface.replaceAll('\\', '/');
              final pattern = normalizedSurface.startsWith('*/')
                  ? normalizedSurface
                  : '${decision.originRegister}/$normalizedSurface';
              return Glob(pattern, context: p.posix).matches(normalized);
            });
          })
          .toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  /// Converts this index to `schema/decision-index.schema.json`.
  Map<String, dynamic> toJson() => _$DecisionIndexToJson(this);

  static IndexedDecisionEdge _resolvePending(
    PendingDecisionEdge edge,
    Map<String, _LoadedRegister> registers,
  ) {
    final separator = edge.targetReference.indexOf('#');
    if (separator <= 0 || separator == edge.targetReference.length - 1) {
      return IndexedDecisionEdge(
        kind: edge.kind,
        reference: edge.targetReference,
        resolution: DecisionIndexEdgeResolution.dangling,
      );
    }

    final targetRegisterName = edge.targetReference.substring(0, separator);
    final targetReference = edge.targetReference.substring(separator + 1);
    final target = registers[targetRegisterName]?.graph.findEntry(
      targetReference,
    );
    return target == null
        ? IndexedDecisionEdge(
            kind: edge.kind,
            reference: edge.targetReference,
            resolution: DecisionIndexEdgeResolution.dangling,
          )
        : IndexedDecisionEdge(
            kind: edge.kind,
            reference: edge.targetReference,
            resolution: DecisionIndexEdgeResolution.resolved,
            targetRegister: targetRegisterName,
            targetSlug: target.slug,
          );
  }

  static int _compareEdges(
    IndexedDecisionEdge left,
    IndexedDecisionEdge right,
  ) {
    final kindOrder = _edgeKindOrder(
      left.kind,
    ).compareTo(_edgeKindOrder(right.kind));
    return kindOrder != 0
        ? kindOrder
        : left.reference.compareTo(right.reference);
  }

  static int _edgeKindOrder(DecisionEdgeKind kind) => switch (kind) {
    DecisionEdgeKind.obsoletes => 0,
    DecisionEdgeKind.updates => 1,
  };

  static String _originRegister(String registerPath) {
    final parts = p.split(p.normalize(registerPath));
    if (parts.length >= 3 &&
        parts.last == 'decisions' &&
        parts[parts.length - 2] == 'docs') {
      return parts[parts.length - 3];
    }
    final name = p.basename(p.normalize(registerPath));
    if (name.isEmpty || name == p.separator) {
      throw DecisionIndexException(
        'cannot infer an origin register from "$registerPath"',
      );
    }
    return name;
  }
}

/// Thrown when register inputs cannot form a deterministic index.
class DecisionIndexException implements Exception {
  /// Creates an index exception with [message].
  const DecisionIndexException(this.message);

  /// What prevented index construction.
  final String message;

  @override
  String toString() => 'DecisionIndexException: $message';
}

final class _LoadedRegister {
  const _LoadedRegister({
    required this.name,
    required this.path,
    required this.graph,
  });

  final String name;
  final String path;
  final DecisionGraph graph;
}
