import 'package:json_annotation/json_annotation.dart';

import 'graph.dart';
import 'lint.dart';
import 'register_union.dart';

part 'index.g.dart';

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
    try {
      return DecisionIndex.fromUnion(
        DecisionRegisterUnion.fromRegisterPaths(registerPaths),
      );
    } on DecisionRegisterUnionException catch (error) {
      throw DecisionIndexException(error.message);
    }
  }

  /// Projects a previously parsed [union] into index schema 2.
  factory DecisionIndex.fromUnion(DecisionRegisterUnion union) {
    final decisions = <IndexedDecision>[];
    for (final register in union.registers) {
      for (final entry in register.graph.entries.values) {
        final edges = <IndexedDecisionEdge>[
          for (final edge in register.graph.outgoingFrom(entry.slug))
            IndexedDecisionEdge(
              kind: edge.kind,
              reference: edge.targetReference,
              resolution: DecisionIndexEdgeResolution.resolved,
              targetRegister: register.originRegister,
              targetSlug: edge.target.slug,
            ),
          for (final edge in register.graph.pendingFrom(entry.slug))
            _resolvePending(edge, union),
        ]..sort(_compareEdges);

        decisions.add(
          IndexedDecision(
            originRegister: register.originRegister,
            originPath: register.originPath,
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
    return DecisionIndex._(
      decisions: decisions,
      diagnostics: union.diagnostics,
    );
  }

  /// Output schema version.
  final int spec;

  /// All decisions in deterministic origin-register/slug order.
  final List<IndexedDecision> decisions;

  /// Entries that could not be parsed, in deterministic file/rule/message order.
  final List<DecisionLintDiagnostic> diagnostics;

  /// Returns only decisions governing [rosterRelativePath].
  DecisionIndex governing(String rosterRelativePath) {
    return DecisionIndex._(
      decisions: decisions
          .where((decision) {
            return matchesDecisionSurface(
              originRegister: decision.originRegister,
              surfaces: decision.surfaces,
              rosterRelativePath: rosterRelativePath,
            );
          })
          .toList(growable: false),
      diagnostics: diagnostics,
    );
  }

  /// Converts this index to `schema/decision-index.schema.json`.
  Map<String, dynamic> toJson() => _$DecisionIndexToJson(this);

  static IndexedDecisionEdge _resolvePending(
    PendingDecisionEdge edge,
    DecisionRegisterUnion union,
  ) {
    final reference = DecisionReference.parse(edge.targetReference);
    final target = reference == null ? null : union.resolveReference(reference);
    return target == null || reference == null
        ? IndexedDecisionEdge(
            kind: edge.kind,
            reference: edge.targetReference,
            resolution: DecisionIndexEdgeResolution.dangling,
          )
        : IndexedDecisionEdge(
            kind: edge.kind,
            reference: edge.targetReference,
            resolution: DecisionIndexEdgeResolution.resolved,
            targetRegister: reference.register,
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
