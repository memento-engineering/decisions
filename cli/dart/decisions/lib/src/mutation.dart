import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
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
  /// check never disagree about which registers are visible. The register is
  /// read, and the default linter parses the candidate, under the register's
  /// limit in [slugLimits].
  const DecisionMutationService({
    DecisionLinter? linter,
    DecisionRoster roster = const DecisionRegisterRoster.empty(),
    DecisionSlugLimits slugLimits = const DecisionSlugLimits(),
  }) : _linter = linter,
       _roster = roster,
       _slugLimits = slugLimits;

  final DecisionLinter? _linter;
  final DecisionRoster _roster;
  final DecisionSlugLimits _slugLimits;

  DecisionLinter get _candidateLinter =>
      _linter ?? DecisionLintService(roster: _roster, slugLimits: _slugLimits);

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
      final graph = DecisionGraph(
        readRegister(
          registerPath,
          maxSlugLength: _slugLimits.forRegister(originRegister),
        ),
      );
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
      final copies = _copyCandidateRegister(
        registerPath: registerPath,
        candidateRegister: candidateRegister,
        replacements: {p.normalize(p.absolute(target.file)): candidate},
      );
      for (final MapEntry(key: sourcePath, value: copy) in copies.entries) {
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

/// Copies every entry file of [registerPath], in file order, into
/// [candidateRegister], writing the text [replacements] holds for a file in
/// place of its bytes.
///
/// [replacements] and the returned map are keyed by each source file's
/// normalized absolute path; the returned map names each source's copy.
Map<String, File> _copyCandidateRegister({
  required String registerPath,
  required Directory candidateRegister,
  required Map<String, String> replacements,
}) {
  final entryFiles =
      Directory(registerPath)
          .listSync()
          .whereType<File>()
          .where((file) => isDecisionEntryFile(file.path))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final copies = <String, File>{};
  for (final entryFile in entryFiles) {
    final copy = File(
      p.join(candidateRegister.path, p.basename(entryFile.path)),
    );
    final sourcePath = p.normalize(p.absolute(entryFile.path));
    final replacement = replacements[sourcePath];
    if (replacement != null) {
      copy.writeAsStringSync(replacement, flush: true);
    } else {
      entryFile.copySync(copy.path);
    }
    copies[sourcePath] = copy;
  }
  return copies;
}

/// Re-points one surface glob across a register after a move.
///
/// A move decides nothing, so no entry is recorded and no force changes: the
/// rewrite touches only the `register.surfaces` list of each entry it names.
final class DecisionResurfaceService {
  /// Creates a service whose candidate register is checked by [linter] when
  /// one is supplied, and otherwise by a linter over [roster]. The register
  /// is read, and the default linter parses, under its limit in [slugLimits].
  const DecisionResurfaceService({
    DecisionLinter? linter,
    DecisionRoster roster = const DecisionRegisterRoster.empty(),
    DecisionSlugLimits slugLimits = const DecisionSlugLimits(),
  }) : _linter = linter,
       _roster = roster,
       _slugLimits = slugLimits;

  final DecisionLinter? _linter;
  final DecisionRoster _roster;
  final DecisionSlugLimits _slugLimits;

  DecisionLinter get _candidateLinter =>
      _linter ?? DecisionLintService(roster: _roster, slugLimits: _slugLimits);

  /// Replaces each surface exactly equal to [from] with [to], in [entries]
  /// when any are named and otherwise in every entry carrying [from], and
  /// returns the rewritten slugs in register file order.
  ///
  /// An entry already carrying [to] keeps it once. Throws
  /// [DecisionMutationException], having written nothing, on every refusal.
  List<String> resurface({
    required String registerPath,
    required String repoRoot,
    required String from,
    required String to,
    Iterable<String> entries = const [],
  }) {
    if (from.isEmpty || to.isEmpty) {
      throw const DecisionMutationException(
        '--from and --to must each be a non-empty glob',
      );
    }
    if (from == to) {
      throw DecisionMutationException(
        '--from and --to are the same glob "$from"',
      );
    }

    final String originRegister;
    final List<DecisionEntry> register;
    try {
      originRegister = decisionOriginRegister(
        p.absolute(p.normalize(registerPath)),
      );
      register = readRegister(
        registerPath,
        maxSlugLength: _slugLimits.forRegister(originRegister),
      );
    } on DecisionRegisterUnionException catch (error) {
      throw DecisionMutationException(error.message);
    } on DecisionParseException catch (error) {
      throw DecisionMutationException(error.toString());
    } on FileSystemException catch (error) {
      throw DecisionMutationException(error.message);
    }

    final bySlug = {for (final entry in register) entry.slug: entry};
    final named = <String>{};
    for (final slug in entries) {
      if (!named.add(slug)) continue;
      final entry = bySlug[slug];
      if (entry == null) {
        throw DecisionMutationException('unknown entry slug "$slug"');
      }
      if (!entry.surfaces.contains(from)) {
        throw DecisionMutationException(
          'entry "$slug" carries no surface "$from"',
        );
      }
    }
    final targets = [
      for (final entry in register)
        if (named.isEmpty
            ? entry.surfaces.contains(from)
            : named.contains(entry.slug))
          entry,
    ];
    if (targets.isEmpty) {
      throw DecisionMutationException('no entry carries surface "$from"');
    }

    final root = p.normalize(p.absolute(repoRoot));
    if (!to.startsWith('roster:') &&
        !DecisionLintService.surfaceMatches(to, root)) {
      throw DecisionMutationException(
        'surface "$to" matched no filesystem entry under $repoRoot',
      );
    }

    final candidates = <String, String>{
      for (final entry in targets)
        p.normalize(p.absolute(entry.file)): _resurfaced(
          File(entry.file).readAsStringSync(),
          from: from,
          to: to,
        ),
    };
    _checkCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      originRegister: originRegister,
      candidates: candidates,
    );
    for (final MapEntry(key: path, value: text) in candidates.entries) {
      File(path).writeAsStringSync(text, flush: true);
    }
    return [for (final entry in targets) entry.slug];
  }

  /// [source] with its surface [from] re-pointed at [to], every other byte
  /// outside the surfaces list kept.
  static String _resurfaced(
    String source, {
    required String from,
    required String to,
  }) {
    final match = DecisionMutationService._frontMatter.firstMatch(source);
    if (match == null) {
      throw const DecisionMutationException('entry has no YAML front matter');
    }
    var frontMatter = match.group(2)!;
    final surfaces = _surfaceNodes(frontMatter);
    final values = [for (final node in surfaces) node.value];
    final fromIndices = [
      for (var i = 0; i < values.length; i++)
        if (values[i] == from) i,
    ];
    final removed = values.contains(to) ? fromIndices : fromIndices.skip(1);
    if (!values.contains(to)) {
      final span = surfaces[fromIndices.first].span;
      frontMatter = frontMatter.replaceRange(
        span.start.offset,
        span.end.offset,
        jsonEncode(to),
      );
    }
    final indices = removed.toList().reversed;
    if (indices.isNotEmpty) {
      final editor = YamlEditor(frontMatter);
      for (final index in indices) {
        editor.remove(['register', 'surfaces', index]);
      }
      frontMatter = editor.toString();
    }
    final rewritten =
        '---${match.group(1)}$frontMatter${match.group(3)}---${match.group(4)}';
    return source.replaceRange(match.start, match.end, rewritten);
  }

  static List<YamlNode> _surfaceNodes(String frontMatter) {
    final document = loadYamlNode(frontMatter);
    final registerBlock = document is YamlMap
        ? document.nodes['register']
        : null;
    final surfaces = registerBlock is YamlMap
        ? registerBlock.nodes['surfaces']
        : null;
    if (surfaces is! YamlList) {
      throw const DecisionMutationException(
        'entry has no register.surfaces list',
      );
    }
    return surfaces.nodes;
  }

  /// Refuses when a rewritten entry would carry more diagnostics of any rule
  /// in the candidate register than it carries in the live one.
  void _checkCandidate({
    required String registerPath,
    required String repoRoot,
    required String originRegister,
    required Map<String, String> candidates,
  }) {
    final root = p.normalize(p.absolute(repoRoot));
    final candidateRoot = Directory.systemTemp.createTempSync(
      'decisions-resurface-',
    );
    final candidateRegister = Directory(
      p.join(candidateRoot.path, originRegister, 'docs', 'decisions'),
    )..createSync(recursive: true);
    try {
      final copies = _copyCandidateRegister(
        registerPath: registerPath,
        candidateRegister: candidateRegister,
        replacements: candidates,
      );
      // Each rewritten entry's repository-relative path, live and candidate.
      final livePaths = <String>{};
      final originalOf = <String, String>{};
      for (final sourcePath in candidates.keys) {
        final original = p.normalize(p.relative(sourcePath, from: root));
        livePaths.add(original);
        originalOf[p.normalize(
              p.relative(p.absolute(copies[sourcePath]!.path), from: root),
            )] =
            original;
      }

      Map<String, Map<String, int>> counts(
        DecisionLintResult result,
        String? Function(String file) pathOf,
      ) {
        final counted = <String, Map<String, int>>{};
        for (final diagnostic in result.diagnostics) {
          if (isRosterWideSurfaceUnmatched(diagnostic)) continue;
          final path = pathOf(p.normalize(diagnostic.file));
          if (path == null) continue;
          final rules = counted.putIfAbsent(path, () => <String, int>{});
          rules[diagnostic.ruleId] = (rules[diagnostic.ruleId] ?? 0) + 1;
        }
        return counted;
      }

      final linter = _candidateLinter;
      final before = counts(
        linter.lint(registerPath: registerPath, repoRoot: repoRoot),
        (file) => livePaths.contains(file) ? file : null,
      );
      final after = counts(
        linter.lint(registerPath: candidateRegister.path, repoRoot: repoRoot),
        (file) => originalOf[file],
      );
      final violations = <String, Set<String>>{};
      for (final MapEntry(key: path, value: rules) in after.entries) {
        for (final MapEntry(key: rule, value: count) in rules.entries) {
          if (count > (before[path]?[rule] ?? 0)) {
            violations.putIfAbsent(path, () => <String>{}).add(rule);
          }
        }
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
