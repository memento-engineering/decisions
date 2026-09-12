import 'dart:math' as math;

import 'entry.dart';
import 'lint.dart';
import 'register_union.dart';

/// JSON schema version emitted by [DecisionSearchHit.toJson].
const decisionSearchOutputSpec = 1;

/// Maximum length of a search snippet, including clipping ellipses.
const decisionSearchSnippetCap = 160;

/// Ergonomic force-state selectors for raw MADR status values.
enum DecisionSearchStatusFilter {
  /// Raw `accepted`.
  accepted,

  /// Raw `superseded by <slug>`.
  obsoleted,

  /// Raw `deprecated`.
  vacated,

  /// Raw `rejected`.
  rejected,
}

/// Optional front-matter filters applied by [DecisionSearchService].
///
/// Values within one category are alternatives. Non-empty categories
/// intersect with every other non-empty category.
final class DecisionSearchFilters {
  /// Creates a filter set.
  const DecisionSearchFilters({
    this.statuses = const <DecisionSearchStatusFilter>[],
    this.dateFrom,
    this.dateThrough,
    this.decisionMakers = const <String>[],
    this.slugs = const <String>[],
    this.surfaces = const <String>[],
    this.obsoletes = const <String>[],
    this.updates = const <String>[],
    this.obsoletedBy = const <String>[],
    this.updatedBy = const <String>[],
  });

  /// Accepted, obsoleted, vacated, or rejected selectors.
  final List<DecisionSearchStatusFilter> statuses;

  /// Inclusive lower date bound in `YYYY-MM-DD` form.
  final String? dateFrom;

  /// Inclusive upper date bound in `YYYY-MM-DD` form.
  final String? dateThrough;

  /// Case-insensitive exact decision-maker names.
  final List<String> decisionMakers;

  /// Exact decision slugs.
  final List<String> slugs;

  /// Roster-qualified paths tested against authored surface globs.
  final List<String> surfaces;

  /// Exact authored `obsoletes` references.
  final List<String> obsoletes;

  /// Exact authored `updates` references.
  final List<String> updates;

  /// Exact cached `obsoleted-by` references.
  final List<String> obsoletedBy;

  /// Exact cached `updated-by` references.
  final List<String> updatedBy;
}

/// One citation-ready lexical match in a decision register.
final class DecisionSearchHit {
  /// Creates a search hit.
  const DecisionSearchHit({
    required this.slug,
    required this.register,
    required this.path,
    required this.status,
    required this.date,
    required this.field,
    required this.snippet,
  });

  /// Canonical decision slug.
  final String slug;

  /// Search-hit output schema version.
  int get spec => decisionSearchOutputSpec;

  /// Origin register namespace.
  final String register;

  /// Source markdown path.
  final String path;

  /// Raw MADR status, without force-state rewriting.
  final String status;

  /// Authored decision date.
  final String date;

  /// First matching field: `title`, `slug`, or `body`.
  final String field;

  /// Single-line excerpt no longer than [decisionSearchSnippetCap].
  final String snippet;

  /// Converts this hit to `schema/decision-search-hit.schema.json`.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'spec': spec,
    'slug': slug,
    'register': register,
    'path': path,
    'status': status,
    'date': date,
    'field': field,
    'snippet': snippet,
  };
}

/// Search hits plus any malformed-entry diagnostics retained by the union.
final class DecisionSearchResult {
  /// Creates a result in deterministic order.
  DecisionSearchResult({
    required List<DecisionSearchHit> hits,
    required List<DecisionLintDiagnostic> diagnostics,
  }) : hits = List<DecisionSearchHit>.unmodifiable(hits),
       diagnostics = List<DecisionLintDiagnostic>.unmodifiable(diagnostics);

  /// Matching decisions in origin-register/slug order.
  final List<DecisionSearchHit> hits;

  /// Entries omitted because they could not be parsed.
  final List<DecisionLintDiagnostic> diagnostics;
}

/// Deterministic OR-token lexical search over parsed decision registers.
final class DecisionSearchService {
  /// Creates the stateless service.
  const DecisionSearchService();

  /// Searches [union], or parses [registerPaths] when no union is supplied.
  ///
  /// Exactly one input form must be supplied. The trimmed query is split on
  /// whitespace; a decision matches when any term is a case-insensitive
  /// substring of its title, slug, or body, in that field precedence.
  DecisionSearchResult search({
    required String query,
    DecisionRegisterUnion? union,
    Iterable<String>? registerPaths,
    DecisionSearchFilters filters = const DecisionSearchFilters(),
  }) {
    if (query.trim().isEmpty) {
      throw ArgumentError.value(query, 'query', 'a search query is required');
    }
    if ((union == null) == (registerPaths == null)) {
      throw ArgumentError(
        'Supply exactly one of union or registerPaths to decision search.',
      );
    }

    final source =
        union ?? DecisionRegisterUnion.fromRegisterPaths(registerPaths!);
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    final hits = <DecisionSearchHit>[];
    for (final register in source.registers) {
      for (final entry in register.graph.entries.values) {
        if (!_passesFilters(register.originRegister, entry, filters)) {
          continue;
        }
        final match = _match(entry, terms);
        if (match == null) continue;
        hits.add(
          DecisionSearchHit(
            slug: entry.slug,
            register: register.originRegister,
            path: entry.file,
            status: entry.status,
            date: entry.date,
            field: match.field,
            snippet: match.snippet,
          ),
        );
      }
    }
    hits.sort((left, right) {
      final registerOrder = left.register.compareTo(right.register);
      return registerOrder != 0
          ? registerOrder
          : left.slug.compareTo(right.slug);
    });
    return DecisionSearchResult(hits: hits, diagnostics: source.diagnostics);
  }
}

bool _passesFilters(
  String originRegister,
  DecisionEntry entry,
  DecisionSearchFilters filters,
) {
  if (filters.statuses.isNotEmpty &&
      !filters.statuses.any((filter) => _matchesStatus(entry.status, filter))) {
    return false;
  }
  final dateFrom = filters.dateFrom;
  if (dateFrom != null && entry.date.compareTo(dateFrom) < 0) return false;
  final dateThrough = filters.dateThrough;
  if (dateThrough != null && entry.date.compareTo(dateThrough) > 0) {
    return false;
  }
  if (!_hasAlternative(
    filters.decisionMakers,
    entry.decisionMakers,
    caseInsensitive: true,
  )) {
    return false;
  }
  if (!_hasAlternative(filters.slugs, <String>[entry.slug])) return false;
  if (filters.surfaces.isNotEmpty &&
      !filters.surfaces.any(
        (surface) => matchesDecisionSurface(
          originRegister: originRegister,
          surfaces: entry.surfaces,
          rosterRelativePath: surface,
        ),
      )) {
    return false;
  }
  if (!_hasAlternative(filters.obsoletes, entry.obsoletes)) return false;
  if (!_hasAlternative(filters.updates, entry.updates)) return false;
  if (!_hasAlternative(filters.obsoletedBy, <String>[
    if (entry.cachedObsoletedBy case final value?) value,
  ])) {
    return false;
  }
  if (!_hasAlternative(filters.updatedBy, entry.cachedUpdatedBy)) return false;
  return true;
}

bool _matchesStatus(String raw, DecisionSearchStatusFilter filter) =>
    switch (filter) {
      DecisionSearchStatusFilter.accepted => raw == 'accepted',
      DecisionSearchStatusFilter.obsoleted => raw.startsWith('superseded by '),
      DecisionSearchStatusFilter.vacated => raw == 'deprecated',
      DecisionSearchStatusFilter.rejected => raw == 'rejected',
    };

bool _hasAlternative(
  List<String> alternatives,
  Iterable<String> values, {
  bool caseInsensitive = false,
}) {
  if (alternatives.isEmpty) return true;
  if (caseInsensitive) {
    final normalized = values.map((value) => value.toLowerCase()).toSet();
    return alternatives.any(
      (alternative) => normalized.contains(alternative.toLowerCase()),
    );
  }
  final available = values.toSet();
  return alternatives.any(available.contains);
}

({String field, String snippet})? _match(
  DecisionEntry entry,
  List<String> terms,
) {
  final title = _title(entry.body);
  final fields = <(String, String)>[
    if (title != null) ('title', title),
    ('slug', entry.slug),
    ('body', entry.body),
  ];
  for (final (field, value) in fields) {
    final match = _firstMatch(value, terms);
    if (match == null) continue;
    return (
      field: field,
      snippet: _snippet(value, match.offset, match.length, terms),
    );
  }
  return null;
}

String? _title(String body) {
  final match = RegExp(
    r'^#(?!#)\s+(.+?)\s*#*\s*$',
    multiLine: true,
  ).firstMatch(body);
  return match?.group(1)?.trim();
}

({int offset, int length})? _firstMatch(String value, List<String> terms) {
  final lower = value.toLowerCase();
  var offset = -1;
  var length = 0;
  for (final term in terms) {
    final candidate = lower.indexOf(term);
    if (candidate >= 0 && (offset < 0 || candidate < offset)) {
      offset = candidate;
      length = term.length;
    }
  }
  return offset < 0 ? null : (offset: offset, length: length);
}

String _snippet(
  String value,
  int matchOffset,
  int matchLength,
  List<String> terms,
) {
  final lineStart = value.lastIndexOf('\n', matchOffset) + 1;
  final newlineAt = value.indexOf('\n', matchOffset);
  final lineEnd = newlineAt < 0 ? value.length : newlineAt;
  final line = value
      .substring(lineStart, lineEnd)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (line.length <= decisionSearchSnippetCap) return line;

  final normalizedMatch = _firstMatch(line, terms);
  final fallbackAt = matchOffset - lineStart;
  final at = normalizedMatch?.offset ?? (fallbackAt < 0 ? 0 : fallbackAt);
  final length = normalizedMatch?.length ?? matchLength;
  final contentCap = decisionSearchSnippetCap - 2;
  final spare = contentCap - length;
  var from = at - (spare < 0 ? 0 : spare ~/ 2);
  from = from.clamp(1, math.max(1, line.length - contentCap - 1)).toInt();
  var to = from + contentCap;
  if (to > line.length) to = line.length;

  if (from == 1 && at < decisionSearchSnippetCap - 1) {
    from = 0;
    to = decisionSearchSnippetCap - 1;
  } else if (to == line.length - 1 &&
      at >= line.length - decisionSearchSnippetCap) {
    to = line.length;
    from = line.length - (decisionSearchSnippetCap - 1);
  }

  final prefix = from > 0 ? '…' : '';
  final suffix = to < line.length ? '…' : '';
  final snippet = '$prefix${line.substring(from, to).trim()}$suffix';
  return snippet.length <= decisionSearchSnippetCap
      ? snippet
      : snippet.substring(0, decisionSearchSnippetCap);
}
