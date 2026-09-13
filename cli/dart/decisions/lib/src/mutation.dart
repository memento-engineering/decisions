import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import 'entry.dart';
import 'graph.dart';
import 'lint.dart';
import 'register_union.dart';

/// Cache-writing operations over an existing decision register.
///
/// Every [successor] is a local slug, or `<repo>#<slug>` for a successor that
/// lives in another register of the roster.
abstract interface class DecisionMutator {
  /// Marks [target] as entirely replaced by [successor].
  void obsolete({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  });

  /// Records [successor] as an amendment while [target] remains accepted.
  void update({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  });

  /// Withdraws [target] after a concrete [successor] entry has been recorded.
  void vacate({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  });
}

/// A requested force mutation was invalid and no target file was changed.
final class DecisionMutationException implements Exception {
  /// Creates a mutation failure carrying [message].
  const DecisionMutationException(this.message);

  /// Why the mutation was refused.
  final String message;

  @override
  String toString() => 'DecisionMutationException: $message';
}

/// Transactional writer for the three permitted decision-force operations.
final class DecisionMutationService implements DecisionMutator {
  /// Creates a service resolving `<repo>#<slug>` successors through [roster].
  ///
  /// The candidate register is checked by [linter] when one is supplied, and
  /// otherwise by a linter over the same [roster], so the mutation and the
  /// check never disagree about which registers are visible.
  const DecisionMutationService({
    DecisionLinter? linter,
    DecisionRoster roster = const DecisionRegisterRoster.empty(),
  }) : _linter = linter,
       _roster = roster;

  final DecisionLinter? _linter;
  final DecisionRoster _roster;

  DecisionLinter get _candidateLinter =>
      _linter ?? DecisionLintService(roster: _roster);

  static final _frontMatter = RegExp(
    r'^---(\r?\n)(.*?)(\r?\n)---(\r?\n)',
    dotAll: true,
  );

  @override
  void obsolete({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  }) {
    final context = _context(
      registerPath: registerPath,
      target: target,
      successor: successor,
    );
    final obsoleting = context.obsoletedBy;
    if (obsoleting.length != 1 ||
        obsoleting.single != context.successorReference) {
      throw DecisionMutationException(
        '"${context.successorReference}" must be the sole entry whose authored '
        'obsoletes edge targets "${context.target.slug}"',
      );
    }

    final candidate = _rewriteCache(
      File(context.target.file).readAsStringSync(),
      [
        (
          path: <Object>['status'],
          value: 'superseded by ${context.successorReference}',
        ),
        (
          path: <Object>['register', 'obsoleted-by'],
          value: context.successorReference,
        ),
      ],
    );
    _commitCleanCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      context: context,
      candidate: candidate,
    );
  }

  @override
  void update({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  }) {
    final context = _context(
      registerPath: registerPath,
      target: target,
      successor: successor,
    );
    final updatedBy = context.updatedBy;
    if (!updatedBy.contains(context.successorReference)) {
      throw DecisionMutationException(
        '"${context.successorReference}" must author an updates edge to '
        '"${context.target.slug}"',
      );
    }

    final candidate = _rewriteCache(
      File(context.target.file).readAsStringSync(),
      [
        (path: <Object>['register', 'updated-by'], value: updatedBy),
      ],
    );
    _commitCleanCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      context: context,
      candidate: candidate,
    );
  }

  @override
  void vacate({
    required String registerPath,
    required String repoRoot,
    required String target,
    required String successor,
  }) {
    final context = _context(
      registerPath: registerPath,
      target: target,
      successor: successor,
    );
    final candidate = _rewriteCache(
      File(context.target.file).readAsStringSync(),
      [
        (path: <Object>['status'], value: 'deprecated'),
      ],
    );
    _commitCleanCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      context: context,
      candidate: candidate,
    );
  }

  _ForceContext _context({
    required String registerPath,
    required String target,
    required String successor,
  }) {
    if (successor.isEmpty || successor == 'none') {
      throw const DecisionMutationException(
        'a concrete successor slug is required; publish a no-rule decision '
        'entry and pass its slug instead of "none"',
      );
    }

    try {
      final originRegister = decisionOriginRegister(
        p.absolute(p.normalize(registerPath)),
      );
      final graph = DecisionGraph(readRegister(registerPath));
      final targetEntry = graph.entries[target];
      if (targetEntry == null) {
        throw DecisionMutationException('unknown target slug "$target"');
      }
      if (targetEntry.status != 'accepted') {
        throw DecisionMutationException(
          'target "$target" must currently be accepted',
        );
      }
      final localSuccessor = _resolveSuccessor(
        graph: graph,
        originRegister: originRegister,
        target: targetEntry,
        successor: successor,
      );
      return _ForceContext(
        roster: _roster,
        graph: graph,
        originRegister: originRegister,
        target: targetEntry,
        localSuccessor: localSuccessor,
        successorReference: successor,
      );
    } on DecisionMutationException {
      rethrow;
    } on DecisionRegisterUnionException catch (error) {
      throw DecisionMutationException(error.message);
    } on DecisionParseException catch (error) {
      throw DecisionMutationException(error.toString());
    } on DecisionGraphException catch (error) {
      throw DecisionMutationException(error.toString());
    } on FileSystemException catch (error) {
      throw DecisionMutationException(error.message);
    }
  }

  /// Resolves [successor] and returns its entry when it is local, or null when
  /// it is a `<repo>#<slug>` successor resolved through the roster.
  DecisionEntry? _resolveSuccessor({
    required DecisionGraph graph,
    required String originRegister,
    required DecisionEntry target,
    required String successor,
  }) {
    if (!DecisionReference.isQualified(successor)) {
      final successorEntry = graph.entries[successor];
      if (successorEntry == null) {
        throw DecisionMutationException('unknown successor slug "$successor"');
      }
      if (identical(target, successorEntry)) {
        throw const DecisionMutationException(
          'target and successor must be distinct entries',
        );
      }
      if (!graph.isBinding(successorEntry.slug)) {
        throw DecisionMutationException(
          'successor "$successor" must be binding',
        );
      }
      return successorEntry;
    }

    final reference = DecisionReference.parse(successor);
    if (reference == null) {
      throw DecisionMutationException(
        'malformed successor "$successor"; a cross-register successor is '
        'spelled "<repo>#<slug>"',
      );
    }
    if (reference.register == originRegister) {
      throw DecisionMutationException(
        'successor "$successor" names this register; pass the bare slug '
        '"${reference.reference}"',
      );
    }
    final register = _roster.findRegister(reference.register);
    if (register == null) {
      throw DecisionMutationException(
        'unknown successor register "${reference.register}"; it is not in '
        'this roster',
      );
    }
    final successorEntry = register.graph.findEntry(reference.reference);
    if (successorEntry == null) {
      throw DecisionMutationException(
        'unknown successor "$successor" in roster register '
        '"${reference.register}"',
      );
    }
    if (!register.graph.isBinding(successorEntry.slug)) {
      throw DecisionMutationException('successor "$successor" must be binding');
    }
    return null;
  }

  String _rewriteCache(
    String source,
    List<({List<Object> path, Object? value})> changes,
  ) {
    final match = _frontMatter.firstMatch(source);
    if (match == null) {
      throw const DecisionMutationException('entry has no YAML front matter');
    }
    final editor = YamlEditor(match.group(2)!);
    for (final change in changes) {
      editor.update(change.path, change.value);
    }
    final rewrittenFrontMatter =
        '---${match.group(1)}$editor${match.group(3)}---${match.group(4)}';
    return source.replaceRange(match.start, match.end, rewrittenFrontMatter);
  }

  void _commitCleanCandidate({
    required String registerPath,
    required String repoRoot,
    required _ForceContext context,
    required String candidate,
  }) {
    final target = context.target;
    final successor = context.localSuccessor;
    final candidateRoot = Directory.systemTemp.createTempSync(
      'decisions-mutation-',
    );
    // The candidate keeps the target register's own `<repo>/docs/decisions`
    // shape so it lints under the same origin register, and therefore against
    // the same cross-register edges, as the register it will replace.
    final candidateRegister = Directory(
      p.join(candidateRoot.path, context.originRegister, 'docs', 'decisions'),
    )..createSync(recursive: true);
    try {
      final root = p.normalize(p.absolute(repoRoot));
      final successorSourcePath = successor == null
          ? null
          : p.normalize(p.absolute(successor.file));
      final touchedSourcePaths = {
        p.normalize(p.absolute(target.file)),
        if (successorSourcePath != null) successorSourcePath,
      };
      final touchedCandidatePaths = <String, String>{};
      String? successorCandidatePath;
      final entryFiles =
          Directory(registerPath)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.md'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final entryFile in entryFiles) {
        final copy = File(
          p.join(candidateRegister.path, p.basename(entryFile.path)),
        );
        final sourcePath = p.normalize(p.absolute(entryFile.path));
        if (p.equals(sourcePath, p.normalize(p.absolute(target.file)))) {
          copy.writeAsStringSync(candidate, flush: true);
        } else {
          entryFile.copySync(copy.path);
        }
        if (touchedSourcePaths.contains(sourcePath)) {
          final candidatePath = p.normalize(
            p.relative(p.absolute(copy.path), from: root),
          );
          touchedCandidatePaths[candidatePath] = p.normalize(
            p.relative(sourcePath, from: root),
          );
          if (successorSourcePath != null &&
              p.equals(sourcePath, successorSourcePath)) {
            successorCandidatePath = candidatePath;
          }
        }
      }

      final result = _candidateLinter.lint(
        registerPath: candidateRegister.path,
        repoRoot: repoRoot,
      );
      final violations = <String, Set<String>>{};
      for (final diagnostic in result.diagnostics) {
        if (isRosterWideSurfaceUnmatched(diagnostic)) continue;
        final diagnosticPath = p.normalize(diagnostic.file);
        if (diagnosticPath == successorCandidatePath &&
            diagnostic.ruleId == DecisionLintRules.forceUpdatedBy) {
          continue;
        }
        final originalPath = touchedCandidatePaths[diagnosticPath];
        if (originalPath == null) continue;
        violations
            .putIfAbsent(originalPath, () => <String>{})
            .add(diagnostic.ruleId);
      }
      if (violations.isNotEmpty) {
        final paths = violations.keys.toList()..sort();
        final summary = paths
            .map((path) {
              final rules = violations[path]!.toList()..sort();
              return '$path [${rules.join(', ')}]';
            })
            .join('; ');
        throw DecisionMutationException(
          'candidate register is not clean: $summary',
        );
      }
      File(target.file).writeAsStringSync(candidate, flush: true);
    } on DecisionMutationException {
      rethrow;
    } on FileSystemException catch (error) {
      throw DecisionMutationException(error.message);
    } finally {
      if (candidateRoot.existsSync()) {
        candidateRoot.deleteSync(recursive: true);
      }
    }
  }
}

/// One resolved force operation: its target, its successor, and the caches the
/// register must carry once the operation lands.
final class _ForceContext {
  _ForceContext({
    required DecisionRoster roster,
    required DecisionGraph graph,
    required this.originRegister,
    required this.target,
    required this.localSuccessor,
    required this.successorReference,
  }) : obsoletedBy = expectedForceCache(
         roster: roster,
         originRegister: originRegister,
         target: target,
         localSources: graph.obsoletedBy(target.slug),
         cached: target.cachedObsoletedBy == null
             ? const <String>[]
             : <String>[target.cachedObsoletedBy!],
         kind: DecisionEdgeKind.obsoletes,
       ),
       updatedBy = expectedForceCache(
         roster: roster,
         originRegister: originRegister,
         target: target,
         localSources: graph.updatedBy(target.slug),
         cached: target.cachedUpdatedBy,
         kind: DecisionEdgeKind.updates,
       );

  /// The namespace the target register publishes under.
  final String originRegister;

  /// The entry whose cache this operation writes.
  final DecisionEntry target;

  /// The successor entry when it lives in the target's own register, and null
  /// when it was resolved through the roster.
  final DecisionEntry? localSuccessor;

  /// The successor as the operator spelled it: a slug, or `<repo>#<slug>`.
  final String successorReference;

  /// References that obsolete [target] once this operation lands.
  final List<String> obsoletedBy;

  /// References that update [target] once this operation lands.
  final List<String> updatedBy;
}
