import 'entry.dart';

/// The two authored relation types in a decision register.
enum DecisionEdgeKind {
  /// The source entirely replaces the target.
  obsoletes,

  /// The source substantively amends a target that remains in force.
  updates,
}

/// Force derived for an entry in a [DecisionGraph].
enum DecisionForce {
  /// The entry remains in force.
  binding,

  /// A resolved authored edge replaces the entry.
  superseded,

  /// The entry has an explicit deprecated status.
  vacated,

  /// The entry has an explicit rejected status.
  rejected,
}

/// One authored edge whose target resolves inside this register.
final class DecisionEdge {
  /// Creates a resolved edge.
  const DecisionEdge({
    required this.source,
    required this.target,
    required this.targetReference,
    required this.kind,
  });

  /// The entry that authored the edge.
  final DecisionEntry source;

  /// The locally resolved target entry.
  final DecisionEntry target;

  /// The target spelling in the source entry, including a legacy id when used.
  final String targetReference;

  /// Whether this edge obsoletes or updates its target.
  final DecisionEdgeKind kind;
}

/// One authored cross-register edge awaiting a roster-aware resolver.
final class PendingDecisionEdge {
  /// Creates a pending edge.
  const PendingDecisionEdge({
    required this.source,
    required this.targetReference,
    required this.kind,
  });

  /// The entry that authored the edge.
  final DecisionEntry source;

  /// The unresolved `<repo>#<slug>` reference.
  final String targetReference;

  /// Whether this edge obsoletes or updates its target.
  final DecisionEdgeKind kind;
}

/// Thrown when a local register cannot form an unambiguous graph.
class DecisionGraphException implements Exception {
  /// Creates a graph exception with [message].
  const DecisionGraphException(this.message);

  /// What prevented graph construction or lookup.
  final String message;

  @override
  String toString() => 'DecisionGraphException: $message';
}

/// An immutable navigable graph over one parsed decision register.
final class DecisionGraph {
  /// Resolves [entries] by slug and legacy id and builds typed relations.
  factory DecisionGraph(Iterable<DecisionEntry> entries) {
    final entryList = List<DecisionEntry>.unmodifiable(entries);
    final bySlug = <String, DecisionEntry>{};

    for (final entry in entryList) {
      final previous = bySlug[entry.slug];
      if (previous != null) {
        throw DecisionGraphException(
          'duplicate slug "${entry.slug}" in '
          '"${previous.file}" and "${entry.file}"',
        );
      }
      bySlug[entry.slug] = entry;
    }

    final byReference = <String, DecisionEntry>{...bySlug};
    for (final entry in entryList) {
      final legacyId = entry.legacyId;
      if (legacyId == null) continue;
      final previous = byReference[legacyId];
      if (previous != null) {
        throw DecisionGraphException(
          'duplicate reference "$legacyId" in '
          '"${previous.file}" and "${entry.file}"',
        );
      }
      byReference[legacyId] = entry;
    }

    final edges = <DecisionEdge>[];
    final pendingEdges = <PendingDecisionEdge>[];
    for (final source in entryList) {
      _addEdges(
        source: source,
        references: source.obsoletes,
        kind: DecisionEdgeKind.obsoletes,
        byReference: byReference,
        edges: edges,
        pendingEdges: pendingEdges,
      );
      _addEdges(
        source: source,
        references: source.updates,
        kind: DecisionEdgeKind.updates,
        byReference: byReference,
        edges: edges,
        pendingEdges: pendingEdges,
      );
    }

    return DecisionGraph._(
      entries: Map<String, DecisionEntry>.unmodifiable(bySlug),
      references: Map<String, DecisionEntry>.unmodifiable(byReference),
      edges: List<DecisionEdge>.unmodifiable(edges),
      pendingEdges: List<PendingDecisionEdge>.unmodifiable(pendingEdges),
    );
  }

  DecisionGraph._({
    required Map<String, DecisionEntry> entries,
    required Map<String, DecisionEntry> references,
    required List<DecisionEdge> edges,
    required List<PendingDecisionEdge> pendingEdges,
  }) : _entries = entries,
       _references = references,
       _edges = edges,
       _pendingEdges = pendingEdges;

  final Map<String, DecisionEntry> _entries;
  final Map<String, DecisionEntry> _references;
  final List<DecisionEdge> _edges;
  final List<PendingDecisionEdge> _pendingEdges;

  /// Entries keyed by their authored slug.
  Map<String, DecisionEntry> get entries => _entries;

  /// Every edge resolved inside this register.
  List<DecisionEdge> get edges => _edges;

  /// Cross-register edges awaiting a multi-register resolver.
  List<PendingDecisionEdge> get pendingEdges => _pendingEdges;

  /// Resolves a local slug or legacy id.
  DecisionEntry entry(String reference) {
    final result = _references[reference];
    if (result == null) {
      throw DecisionGraphException('unknown entry reference "$reference"');
    }
    return result;
  }

  /// Resolved edges authored by [reference], optionally restricted by [kind].
  List<DecisionEdge> outgoingFrom(String reference, {DecisionEdgeKind? kind}) {
    final source = entry(reference);
    return List<DecisionEdge>.unmodifiable(
      _edges.where(
        (edge) =>
            identical(edge.source, source) &&
            (kind == null || edge.kind == kind),
      ),
    );
  }

  /// Resolved edges targeting [reference], optionally restricted by [kind].
  List<DecisionEdge> incomingTo(String reference, {DecisionEdgeKind? kind}) {
    final target = entry(reference);
    return List<DecisionEdge>.unmodifiable(
      _edges.where(
        (edge) =>
            identical(edge.target, target) &&
            (kind == null || edge.kind == kind),
      ),
    );
  }

  /// Pending cross-register edges authored by [reference].
  List<PendingDecisionEdge> pendingFrom(
    String reference, {
    DecisionEdgeKind? kind,
  }) {
    final source = entry(reference);
    return List<PendingDecisionEdge>.unmodifiable(
      _pendingEdges.where(
        (edge) =>
            identical(edge.source, source) &&
            (kind == null || edge.kind == kind),
      ),
    );
  }

  /// Entries that entirely replace [reference].
  List<DecisionEntry> obsoletedBy(String reference) =>
      List<DecisionEntry>.unmodifiable(
        incomingTo(
          reference,
          kind: DecisionEdgeKind.obsoletes,
        ).map((edge) => edge.source),
      );

  /// Entries that substantively amend [reference].
  List<DecisionEntry> updatedBy(String reference) =>
      List<DecisionEntry>.unmodifiable(
        incomingTo(
          reference,
          kind: DecisionEdgeKind.updates,
        ).map((edge) => edge.source),
      );

  /// Derives the current force of [reference] from authored graph relations.
  ///
  /// Incoming obsoletes edges win over cached status. A cached
  /// `superseded by ...` value without such an edge is stale and therefore
  /// does not remove force. Deprecated and rejected remain explicit
  /// non-binding status states.
  DecisionForce forceOf(String reference) {
    if (incomingTo(reference, kind: DecisionEdgeKind.obsoletes).isNotEmpty) {
      return DecisionForce.superseded;
    }

    final status = entry(reference).status;
    return switch (status) {
      'accepted' => DecisionForce.binding,
      'deprecated' => DecisionForce.vacated,
      'rejected' => DecisionForce.rejected,
      final value when value.startsWith('superseded by ') =>
        DecisionForce.binding,
      _ => throw DecisionGraphException('unsupported status "$status"'),
    };
  }

  /// Whether [reference] remains in force according to the graph.
  bool isBinding(String reference) =>
      forceOf(reference) == DecisionForce.binding;

  static void _addEdges({
    required DecisionEntry source,
    required Iterable<String> references,
    required DecisionEdgeKind kind,
    required Map<String, DecisionEntry> byReference,
    required List<DecisionEdge> edges,
    required List<PendingDecisionEdge> pendingEdges,
  }) {
    for (final reference in references) {
      if (reference.contains('#')) {
        pendingEdges.add(
          PendingDecisionEdge(
            source: source,
            targetReference: reference,
            kind: kind,
          ),
        );
        continue;
      }

      final target = byReference[reference];
      if (target == null) {
        throw DecisionGraphException(
          '"${source.slug}" points at unknown local entry "$reference"',
        );
      }
      edges.add(
        DecisionEdge(
          source: source,
          target: target,
          targetReference: reference,
          kind: kind,
        ),
      );
    }
  }
}
