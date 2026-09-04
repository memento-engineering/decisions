import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;

import 'entry.dart';
import 'graph.dart';

/// UI-drivable contract for decision-register linting.
abstract interface class DecisionLinter {
  /// Validates one register against [repoRoot].
  DecisionLintResult lint({
    required String registerPath,
    required String repoRoot,
  });
}

/// Stable identifiers emitted by [DecisionLintService].
abstract final class DecisionLintRules {
  static const entrySchema = 'entry.schema';
  static const identityFilename = 'identity.filename';
  static const identityDuplicateSlug = 'identity.duplicate-slug';
  static const identityDuplicateReference = 'identity.duplicate-reference';
  static const statusProposed = 'status.proposed';
  static const edgeInvalidReference = 'edge.invalid-reference';
  static const edgeDanglingLocal = 'edge.dangling-local';
  static const edgeAmbiguousLocal = 'edge.ambiguous-local';
  static const forceObsoletedBy = 'force.obsoleted-by';
  static const forceUpdatedBy = 'force.updated-by';
  static const forceStatus = 'force.status';
  static const surfaceUnmatched = 'surface.unmatched';
  static const specUnsupported = 'spec.unsupported';
}

/// One deterministic lint violation.
final class DecisionLintDiagnostic {
  const DecisionLintDiagnostic({
    required this.ruleId,
    required this.file,
    required this.message,
  });

  /// Creates the same per-entry diagnostic used when parsing fails in lint or
  /// another read-only consumer.
  factory DecisionLintDiagnostic.fromParseException(
    DecisionParseException error, {
    String? file,
  }) => DecisionLintDiagnostic(
    ruleId: switch (error.failure) {
      DecisionParseFailure.schema => DecisionLintRules.entrySchema,
      DecisionParseFailure.filename => DecisionLintRules.identityFilename,
    },
    file: file ?? error.file,
    message: error.message,
  );

  /// Orders diagnostics deterministically by file, rule id, then message.
  static int compare(
    DecisionLintDiagnostic left,
    DecisionLintDiagnostic right,
  ) {
    final fileOrder = left.file.compareTo(right.file);
    if (fileOrder != 0) return fileOrder;
    final ruleOrder = left.ruleId.compareTo(right.ruleId);
    if (ruleOrder != 0) return ruleOrder;
    return left.message.compareTo(right.message);
  }

  final String ruleId;
  final String file;
  final String message;

  Map<String, Object> toJson() => {
    'ruleId': ruleId,
    'file': file,
    'message': message,
  };
}

/// Complete lint result for one register.
final class DecisionLintResult {
  DecisionLintResult({
    required this.register,
    required Iterable<DecisionLintDiagnostic> diagnostics,
  }) : diagnostics = List<DecisionLintDiagnostic>.unmodifiable(diagnostics);

  static const schemaVersion = 1;
  final String register;
  final List<DecisionLintDiagnostic> diagnostics;
  bool get isClean => diagnostics.isEmpty;

  Map<String, Object> toJson() => {
    'schemaVersion': schemaVersion,
    'register': register,
    'valid': isClean,
    'diagnostics': [for (final diagnostic in diagnostics) diagnostic.toJson()],
  };
}

/// Graph-aware validation for one decision register.
final class DecisionLintService implements DecisionLinter {
  const DecisionLintService();

  static const supportedSpec = 1;
  static final _localReference = RegExp(
    r'^(?:[a-z0-9]+(?:-[a-z0-9]+)*|A[1-9][0-9]*)$',
  );
  static final _crossReference = RegExp(
    r'^[a-z0-9_.-]+#[a-z0-9]+(?:-[a-z0-9]+)*$',
  );

  @override
  DecisionLintResult lint({
    required String registerPath,
    required String repoRoot,
  }) {
    final root = p.normalize(p.absolute(repoRoot));
    final register = p.normalize(p.absolute(registerPath));
    final diagnostics = <DecisionLintDiagnostic>[];
    final entries = <DecisionEntry>[];
    var graphIsSound = true;
    final directory = Directory(register);

    if (!directory.existsSync()) {
      diagnostics.add(
        DecisionLintDiagnostic(
          ruleId: DecisionLintRules.entrySchema,
          file: _display(register, root),
          message: 'register directory does not exist',
        ),
      );
      return _result(register, root, diagnostics);
    }

    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.md'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    for (final file in files) {
      try {
        final entry = parseEntry(file.path);
        entries.add(entry);
        if (entry.status == 'proposed') {
          diagnostics.add(
            _diagnostic(
              entry,
              root,
              DecisionLintRules.statusProposed,
              'this profile never uses proposed',
            ),
          );
        }
        if (entry.spec > supportedSpec) {
          diagnostics.add(
            _diagnostic(
              entry,
              root,
              DecisionLintRules.specUnsupported,
              'spec ${entry.spec} is newer than supported spec 1',
            ),
          );
        }
        for (final surface in entry.surfaces) {
          if (!_surfaceExists(surface, root)) {
            diagnostics.add(
              _diagnostic(
                entry,
                root,
                DecisionLintRules.surfaceUnmatched,
                'surface "$surface" matched no filesystem entry',
              ),
            );
          }
        }
      } on DecisionParseException catch (error) {
        graphIsSound = false;
        diagnostics.add(
          DecisionLintDiagnostic.fromParseException(
            error,
            file: _display(error.file, root),
          ),
        );
      }
    }

    final bySlug = <String, List<DecisionEntry>>{};
    for (final entry in entries) {
      bySlug.putIfAbsent(entry.slug, () => <DecisionEntry>[]).add(entry);
    }
    final duplicateFiles = <String>{};
    for (final group in bySlug.values.where((group) => group.length > 1)) {
      graphIsSound = false;
      for (final entry in group) {
        duplicateFiles.add(entry.file);
        diagnostics.add(
          _diagnostic(
            entry,
            root,
            DecisionLintRules.identityDuplicateSlug,
            'slug "${entry.slug}" occurs in ${group.length} files',
          ),
        );
      }
    }

    final byReference = <String, List<DecisionEntry>>{};
    for (final entry in entries.where(
      (entry) => !duplicateFiles.contains(entry.file),
    )) {
      for (final reference in [
        entry.slug,
        if (entry.legacyId case final legacyId?) legacyId,
      ]) {
        byReference.putIfAbsent(reference, () => <DecisionEntry>[]).add(entry);
      }
    }
    for (final item in byReference.entries.where(
      (item) => item.value.map((entry) => entry.file).toSet().length > 1,
    )) {
      graphIsSound = false;
      for (final entry in item.value) {
        diagnostics.add(
          _diagnostic(
            entry,
            root,
            DecisionLintRules.identityDuplicateReference,
            'reference "${item.key}" is ambiguous',
          ),
        );
      }
    }

    for (final entry in entries) {
      for (final reference in [...entry.obsoletes, ...entry.updates]) {
        if (_crossReference.hasMatch(reference)) continue;
        if (!_localReference.hasMatch(reference)) {
          graphIsSound = false;
          diagnostics.add(
            _diagnostic(
              entry,
              root,
              DecisionLintRules.edgeInvalidReference,
              'authored reference "$reference" is malformed',
            ),
          );
          continue;
        }
        final targets = byReference[reference] ?? const <DecisionEntry>[];
        if (targets.isEmpty) {
          graphIsSound = false;
          diagnostics.add(
            _diagnostic(
              entry,
              root,
              DecisionLintRules.edgeDanglingLocal,
              'authored reference "$reference" does not resolve',
            ),
          );
        } else if (targets.length > 1) {
          graphIsSound = false;
          diagnostics.add(
            _diagnostic(
              entry,
              root,
              DecisionLintRules.edgeAmbiguousLocal,
              'authored reference "$reference" is ambiguous',
            ),
          );
        }
      }
    }

    if (graphIsSound) {
      _lintForceCache(
        graph: DecisionGraph(entries),
        entries: entries,
        repoRoot: root,
        diagnostics: diagnostics,
      );
    }
    return _result(register, root, diagnostics);
  }

  static void _lintForceCache({
    required DecisionGraph graph,
    required List<DecisionEntry> entries,
    required String repoRoot,
    required List<DecisionLintDiagnostic> diagnostics,
  }) {
    for (final entry in entries) {
      final obsoleting =
          graph.obsoletedBy(entry.slug).map((source) => source.slug).toList()
            ..sort();
      final updating =
          graph.updatedBy(entry.slug).map((source) => source.slug).toList()
            ..sort();

      final expectedObsoletedBy = obsoleting.length == 1
          ? obsoleting.single
          : null;
      if (obsoleting.length > 1 ||
          entry.cachedObsoletedBy != expectedObsoletedBy) {
        diagnostics.add(
          _diagnostic(
            entry,
            repoRoot,
            DecisionLintRules.forceObsoletedBy,
            'cached obsoleted-by does not match ${obsoleting.join(', ')}',
          ),
        );
      }
      if (!_sameReferences(entry.cachedUpdatedBy, updating)) {
        diagnostics.add(
          _diagnostic(
            entry,
            repoRoot,
            DecisionLintRules.forceUpdatedBy,
            'cached updated-by does not match ${updating.join(', ')}',
          ),
        );
      }

      if (obsoleting.length == 1) {
        final expectedStatus = 'superseded by ${obsoleting.single}';
        if (entry.status != expectedStatus) {
          diagnostics.add(
            _diagnostic(
              entry,
              repoRoot,
              DecisionLintRules.forceStatus,
              'cached status must be "$expectedStatus"',
            ),
          );
        }
      } else if (obsoleting.isEmpty &&
          entry.status.startsWith('superseded by ')) {
        diagnostics.add(
          _diagnostic(
            entry,
            repoRoot,
            DecisionLintRules.forceStatus,
            'cached superseded status has no incoming obsoletes edge',
          ),
        );
      } else if (obsoleting.isEmpty &&
          updating.isNotEmpty &&
          entry.status != 'accepted' &&
          entry.status != 'deprecated') {
        diagnostics.add(
          _diagnostic(
            entry,
            repoRoot,
            DecisionLintRules.forceStatus,
            'an updated target must remain accepted unless explicitly vacated',
          ),
        );
      }
    }
  }

  static bool _sameReferences(List<String> cached, List<String> derived) =>
      cached.length == derived.length && cached.toSet().containsAll(derived);

  static bool _surfaceExists(String pattern, String repoRoot) {
    for (final root in _surfaceRoots(pattern, repoRoot)) {
      try {
        if (Glob(pattern).listSync(root: root, followLinks: false).isNotEmpty) {
          return true;
        }
      } on FormatException {
        return false;
      }
    }
    return false;
  }

  static Iterable<String> _surfaceRoots(String pattern, String repoRoot) sync* {
    yield repoRoot;
    final segments = p.split(pattern);
    if (segments.isEmpty) return;
    final qualifier = segments.first;
    var ancestor = Directory(repoRoot).absolute;
    while (ancestor.parent.path != ancestor.path) {
      if (p.basename(ancestor.path) == qualifier) {
        yield ancestor.parent.path;
      }
      ancestor = ancestor.parent;
    }
  }

  static DecisionLintDiagnostic _diagnostic(
    DecisionEntry entry,
    String repoRoot,
    String ruleId,
    String message,
  ) => DecisionLintDiagnostic(
    ruleId: ruleId,
    file: _display(entry.file, repoRoot),
    message: message,
  );

  static DecisionLintResult _result(
    String register,
    String repoRoot,
    List<DecisionLintDiagnostic> diagnostics,
  ) {
    diagnostics.sort(DecisionLintDiagnostic.compare);
    return DecisionLintResult(
      register: _display(register, repoRoot),
      diagnostics: diagnostics,
    );
  }

  static String _display(String path, String repoRoot) =>
      p.normalize(p.relative(p.absolute(path), from: repoRoot));
}
