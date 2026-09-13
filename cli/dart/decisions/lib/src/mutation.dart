import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml_edit/yaml_edit.dart';

import 'entry.dart';
import 'graph.dart';
import 'lint.dart';

/// Cache-writing operations over an existing decision register.
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
  /// Creates a service whose candidate register is checked by [linter].
  const DecisionMutationService({
    DecisionLinter linter = const DecisionLintService(),
  }) : _linter = linter;

  final DecisionLinter _linter;

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
    final obsoleting = context.graph.obsoletedBy(context.target.slug);
    if (obsoleting.length != 1 ||
        !identical(obsoleting.single, context.successor)) {
      throw DecisionMutationException(
        '"${context.successor.slug}" must be the sole entry whose authored '
        'obsoletes edge targets "${context.target.slug}"',
      );
    }

    final candidate = _rewriteCache(
      File(context.target.file).readAsStringSync(),
      [
        (
          path: <Object>['status'],
          value: 'superseded by ${context.successor.slug}',
        ),
        (
          path: <Object>['register', 'obsoleted-by'],
          value: context.successor.slug,
        ),
      ],
    );
    _commitCleanCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      target: context.target,
      successor: context.successor,
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
    final updating = context.graph.updatedBy(context.target.slug);
    if (!updating.any((entry) => identical(entry, context.successor))) {
      throw DecisionMutationException(
        '"${context.successor.slug}" must author an updates edge to '
        '"${context.target.slug}"',
      );
    }
    final updatedBy = updating.map((entry) => entry.slug).toList()..sort();

    final candidate = _rewriteCache(
      File(context.target.file).readAsStringSync(),
      [
        (path: <Object>['register', 'updated-by'], value: updatedBy),
      ],
    );
    _commitCleanCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      target: context.target,
      successor: context.successor,
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
      target: context.target,
      successor: context.successor,
      candidate: candidate,
    );
  }

  ({DecisionGraph graph, DecisionEntry target, DecisionEntry successor})
  _context({
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
      final graph = DecisionGraph(readRegister(registerPath));
      final targetEntry = graph.entries[target];
      if (targetEntry == null) {
        throw DecisionMutationException('unknown target slug "$target"');
      }
      final successorEntry = graph.entries[successor];
      if (successorEntry == null) {
        throw DecisionMutationException('unknown successor slug "$successor"');
      }
      if (identical(targetEntry, successorEntry)) {
        throw const DecisionMutationException(
          'target and successor must be distinct entries',
        );
      }
      if (targetEntry.status != 'accepted') {
        throw DecisionMutationException(
          'target "$target" must currently be accepted',
        );
      }
      if (!graph.isBinding(successorEntry.slug)) {
        throw DecisionMutationException(
          'successor "$successor" must be binding',
        );
      }
      return (graph: graph, target: targetEntry, successor: successorEntry);
    } on DecisionMutationException {
      rethrow;
    } on DecisionParseException catch (error) {
      throw DecisionMutationException(error.toString());
    } on DecisionGraphException catch (error) {
      throw DecisionMutationException(error.toString());
    } on FileSystemException catch (error) {
      throw DecisionMutationException(error.message);
    }
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
    required DecisionEntry target,
    required DecisionEntry successor,
    required String candidate,
  }) {
    final candidateRegister = Directory.systemTemp.createTempSync(
      'decisions-mutation-',
    );
    try {
      final root = p.normalize(p.absolute(repoRoot));
      final touchedSourcePaths = {
        p.normalize(p.absolute(target.file)),
        p.normalize(p.absolute(successor.file)),
      };
      final successorSourcePath = p.normalize(p.absolute(successor.file));
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
          if (p.equals(sourcePath, successorSourcePath)) {
            successorCandidatePath = candidatePath;
          }
        }
      }

      final result = _linter.lint(
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
      if (candidateRegister.existsSync()) {
        candidateRegister.deleteSync(recursive: true);
      }
    }
  }
}
