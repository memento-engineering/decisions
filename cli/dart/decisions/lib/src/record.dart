import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'entry.dart';
import 'graph.dart';
import 'lint.dart';
import 'register_union.dart';

/// Everything an author decides about a new entry; the rest is mechanics.
///
/// Every edge in [obsoletes] and [updates] is a local slug, or `<repo>#<slug>`
/// for a decision in another register of the roster.
final class DecisionDraft {
  /// Creates a draft. A null [date] means today, from the recorder's clock.
  const DecisionDraft({
    required this.slug,
    required this.title,
    required this.surfaces,
    required this.decisionMakers,
    required this.body,
    this.consulted = const <String>[],
    this.informed = const <String>[],
    this.obsoletes = const <String>[],
    this.updates = const <String>[],
    this.bead,
    this.date,
  });

  /// The entry's identity: kebab-case, at most 80 characters.
  final String slug;

  /// The short declarative title, written as the entry's only H1.
  final String title;

  /// Paths or globs the decision governs; at least one.
  final List<String> surfaces;

  /// The people and agent seats that made the call; at least one.
  final List<String> decisionMakers;

  /// People who supplied input.
  final List<String> consulted;

  /// Audiences actually notified.
  final List<String> informed;

  /// AUTHORED edges: decisions this one replaces entirely.
  final List<String> obsoletes;

  /// AUTHORED edges: decisions this one amends, which remain in force.
  final List<String> updates;

  /// The minted decision-type bead id, or null for a trackerless register.
  final String? bead;

  /// The entry date, `YYYY-MM-DD`, or null for today.
  final String? date;

  /// The MADR Markdown after the H1: at least the `Context and Problem
  /// Statement` and `Decision Outcome` sections, and no H1 of its own.
  final String body;
}

/// One force verb the operator still has to run so the target of an authored
/// edge caches the new entry.
final class DecisionNextStep {
  /// Creates a next step for an edge of [kind] onto [target].
  const DecisionNextStep({
    required this.kind,
    required this.target,
    required this.successor,
    this.register,
  });

  /// The authored edge this step completes.
  final DecisionEdgeKind kind;

  /// The target's slug, inside the register the verb runs in.
  final String target;

  /// The successor exactly as the verb expects it: a bare slug in the same
  /// register, or `<repo>#<slug>` from another one.
  final String successor;

  /// The register the verb runs in, or null for the new entry's own register.
  final String? register;

  /// The force verb that writes the target's cache for this edge.
  String get verb => switch (kind) {
    DecisionEdgeKind.obsoletes => 'obsolete',
    DecisionEdgeKind.updates => 'update',
  };

  /// The command line, naming the register to run it in when it is not the
  /// new entry's own.
  String get command {
    final invocation = 'decisions $verb $target --by $successor';
    return switch (register) {
      null => invocation,
      final register => '$invocation (run in register $register)',
    };
  }

  @override
  String toString() => command;
}

/// What [DecisionRecorder.record] wrote.
final class DecisionRecordResult {
  /// Creates a result for the entry written at [path].
  DecisionRecordResult({
    required this.path,
    required this.citation,
    required Iterable<DecisionNextStep> nextSteps,
  }) : nextSteps = List<DecisionNextStep>.unmodifiable(nextSteps);

  /// The written entry file.
  final String path;

  /// The entry's `<repo>#<slug>` citation handle.
  final String citation;

  /// One force verb per authored edge, in authored order.
  final List<DecisionNextStep> nextSteps;
}

/// A new entry was refused and nothing was written.
final class DecisionRecordException implements Exception {
  /// Creates a refusal carrying [message].
  const DecisionRecordException(this.message);

  /// Why the entry was refused.
  final String message;

  @override
  String toString() => 'DecisionRecordException: $message';
}

/// Writes new decision entries into a register.
abstract interface class DecisionRecorder {
  /// Validates [draft] against the register at [registerPath] and writes it
  /// with birth values, or throws [DecisionRecordException] having written
  /// nothing. Surfaces resolve against [repoRoot].
  DecisionRecordResult record({
    required String registerPath,
    required String repoRoot,
    required DecisionDraft draft,
  });
}

/// The write mechanics of recording a decision: identity, collision, body
/// shape, birth values, quoting and a first-write lint.
///
/// Judgement — whether to record, which surfaces, which edges, who decided —
/// stays with the author; this service only refuses what is mechanically
/// wrong.
final class DecisionRecordService implements DecisionRecorder {
  /// Creates a service whose default date comes from [clock] (local time by
  /// default) and whose candidate lint resolves `<repo>#<slug>` edges
  /// through [roster].
  ///
  /// The candidate register is checked by [linter] when one is supplied, and
  /// otherwise by a linter over the same [roster].
  DecisionRecordService({
    DateTime Function()? clock,
    DecisionLinter? linter,
    DecisionRoster roster = const DecisionRegisterRoster.empty(),
  }) : _clock = clock ?? DateTime.now,
       _linter = linter,
       _roster = roster;

  final DateTime Function() _clock;
  final DecisionLinter? _linter;
  final DecisionRoster _roster;

  /// The longest slug the format admits.
  static const maxSlugLength = 80;

  /// The headings every body must carry at level two.
  static const requiredSections = <String>[
    'Context and Problem Statement',
    'Decision Outcome',
  ];

  static final _slugPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
  static final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _fence = RegExp(r'^ {0,3}(```|~~~)');
  static final _h1 = RegExp(r'^ {0,3}#(?:[ \t]|$)');
  static final _h2 = RegExp(r'^ {0,3}##[ \t]+(.*?)(?:[ \t]+#+)?[ \t]*$');

  @override
  DecisionRecordResult record({
    required String registerPath,
    required String repoRoot,
    required DecisionDraft draft,
  }) {
    _checkSlug(draft.slug);
    final title = draft.title.trim();
    if (title.isEmpty || title.contains('\n')) {
      throw const DecisionRecordException('the title must be one line');
    }
    if (draft.surfaces.isEmpty) {
      throw const DecisionRecordException('at least one surface is required');
    }
    if (draft.decisionMakers.isEmpty) {
      throw const DecisionRecordException(
        'at least one decision-maker is required',
      );
    }
    final date = draft.date ?? _today();
    if (!_isValidDate(date)) {
      throw DecisionRecordException('invalid date "$date"; use YYYY-MM-DD');
    }

    final String originRegister;
    try {
      originRegister = decisionOriginRegister(
        p.absolute(p.normalize(registerPath)),
      );
    } on DecisionRegisterUnionException catch (error) {
      throw DecisionRecordException(error.message);
    }
    final fileName = '$date-${draft.slug}.md';
    final path = p.join(registerPath, fileName);
    final existing = _existingEntries(registerPath);
    _checkCollision(draft.slug, path, existing);
    final body = _checkBody(draft.body);
    _checkOwnRegisterEdges(draft, originRegister);

    final source = renderEntry(draft: draft, date: date, body: body);
    _lintCandidate(
      registerPath: registerPath,
      repoRoot: repoRoot,
      originRegister: originRegister,
      fileName: fileName,
      source: source,
    );

    try {
      Directory(registerPath).createSync(recursive: true);
      File(path).writeAsStringSync(source, flush: true);
    } on FileSystemException catch (error) {
      throw DecisionRecordException('cannot write $path: ${error.message}');
    }
    return DecisionRecordResult(
      path: path,
      citation: '$originRegister#${draft.slug}',
      nextSteps: [
        for (final reference in draft.obsoletes)
          _nextStep(
            DecisionEdgeKind.obsoletes,
            reference,
            draft.slug,
            originRegister,
            existing,
          ),
        for (final reference in draft.updates)
          _nextStep(
            DecisionEdgeKind.updates,
            reference,
            draft.slug,
            originRegister,
            existing,
          ),
      ],
    );
  }

  /// Renders the entry file for [draft]: front matter with birth values, the
  /// H1, then [body].
  ///
  /// Every free-text value is a double-quoted YAML scalar, so names and globs
  /// carrying `:`, `#`, quotes or YAML keywords round-trip unchanged.
  static String renderEntry({
    required DecisionDraft draft,
    required String date,
    required String body,
  }) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('status: accepted')
      ..writeln('date: $date');
    _writeList(buffer, 'decision-makers', draft.decisionMakers, indent: '');
    _writeList(buffer, 'consulted', draft.consulted, indent: '');
    _writeList(buffer, 'informed', draft.informed, indent: '');
    buffer
      ..writeln('register:')
      ..writeln('  spec: ${DecisionLintService.supportedSpec}')
      ..writeln('  slug: ${draft.slug}');
    _writeList(buffer, 'surfaces', draft.surfaces, indent: '  ');
    _writeList(buffer, 'obsoletes', draft.obsoletes, indent: '  ');
    _writeList(buffer, 'updates', draft.updates, indent: '  ');
    buffer
      ..writeln('  obsoleted-by: null')
      ..writeln('  updated-by: []')
      ..writeln('  bead: ${_scalar(draft.bead)}')
      ..writeln('  legacy-id: null')
      ..writeln('---')
      ..writeln()
      ..writeln('# ${draft.title.trim()}')
      ..writeln()
      ..writeln(body);
    return buffer.toString();
  }

  static void _writeList(
    StringBuffer buffer,
    String key,
    List<String> values, {
    required String indent,
  }) {
    if (values.isEmpty) {
      buffer.writeln('$indent$key: []');
      return;
    }
    buffer.writeln('$indent$key:');
    for (final value in values) {
      buffer.writeln('$indent  - ${_scalar(value)}');
    }
  }

  /// A JSON string literal is a valid YAML double-quoted scalar.
  static String _scalar(String? value) =>
      value == null ? 'null' : jsonEncode(value);

  String _today() {
    final now = _clock();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
        '${two(now.day)}';
  }

  static bool _isValidDate(String value) {
    if (!_datePattern.hasMatch(value)) return false;
    final parts = value.split('-').map(int.parse).toList();
    final parsed = DateTime.tryParse(value);
    return parsed != null &&
        parsed.year == parts[0] &&
        parsed.month == parts[1] &&
        parsed.day == parts[2];
  }

  static void _checkSlug(String slug) {
    if (slug.length > maxSlugLength || !_slugPattern.hasMatch(slug)) {
      throw DecisionRecordException(
        'invalid slug "$slug"; use at most $maxSlugLength characters of '
        'lowercase kebab-case',
      );
    }
  }

  /// The parseable entries already in the register; none when it is absent.
  static List<DecisionEntry> _existingEntries(String registerPath) {
    if (!Directory(registerPath).existsSync()) return const <DecisionEntry>[];
    try {
      return readRegister(registerPath, onParseError: (_) {});
    } on FileSystemException catch (error) {
      throw DecisionRecordException(error.message);
    }
  }

  static void _checkCollision(
    String slug,
    String path,
    List<DecisionEntry> existing,
  ) {
    final String? collision;
    if (File(path).existsSync()) {
      collision = path;
    } else {
      collision = existing
          .where((entry) => entry.slug == slug)
          .map((entry) => entry.file)
          .firstOrNull;
    }
    if (collision != null) {
      throw DecisionRecordException(
        'slug "$slug" is already recorded in $collision; cite it if it is the '
        'same decision, or choose a slug for a substantively different one',
      );
    }
  }

  /// Returns [body] trimmed, or refuses a body without the required sections
  /// or with an H1 of its own. Lines inside fenced code blocks are not
  /// headings.
  static String _checkBody(String body) {
    final trimmed = body.trim();
    final sections = <String>{};
    var fenced = false;
    for (final line in const LineSplitter().convert(trimmed)) {
      if (_fence.hasMatch(line)) {
        fenced = !fenced;
        continue;
      }
      if (fenced) continue;
      if (_h1.hasMatch(line)) {
        throw const DecisionRecordException(
          'the body must not carry an H1; the title becomes the H1',
        );
      }
      if (_h2.firstMatch(line) case final match?) {
        sections.add(match.group(1)!);
      }
    }
    final missing = requiredSections.where((name) => !sections.contains(name));
    if (missing.isNotEmpty) {
      throw DecisionRecordException(
        'the body lacks the level-two section(s): '
        '${missing.map((name) => '"## $name"').join(', ')}',
      );
    }
    return trimmed;
  }

  static void _checkOwnRegisterEdges(
    DecisionDraft draft,
    String originRegister,
  ) {
    for (final reference in [...draft.obsoletes, ...draft.updates]) {
      final qualified = DecisionReference.parse(reference);
      if (qualified != null && qualified.register == originRegister) {
        throw DecisionRecordException(
          'edge "$reference" names this register; pass the bare slug '
          '"${qualified.reference}"',
        );
      }
    }
  }

  /// Lints a copy of the register plus the new entry, in the register's own
  /// `<repo>/docs/decisions` shape, and refuses on any diagnostic against the
  /// new entry. Dirt elsewhere in the register is not this write's to fix.
  void _lintCandidate({
    required String registerPath,
    required String repoRoot,
    required String originRegister,
    required String fileName,
    required String source,
  }) {
    final candidateRoot = Directory.systemTemp.createTempSync('decisions-new-');
    final candidateRegister = Directory(
      p.join(candidateRoot.path, originRegister, 'docs', 'decisions'),
    )..createSync(recursive: true);
    try {
      final register = Directory(registerPath);
      if (register.existsSync()) {
        for (final file in register.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.md'),
        )) {
          file.copySync(p.join(candidateRegister.path, p.basename(file.path)));
        }
      }
      final candidate = File(p.join(candidateRegister.path, fileName))
        ..writeAsStringSync(source, flush: true);
      final root = p.normalize(p.absolute(repoRoot));
      final candidatePath = p.normalize(
        p.relative(p.absolute(candidate.path), from: root),
      );

      final linter = _linter ?? DecisionLintService(roster: _roster);
      final result = linter.lint(
        registerPath: candidateRegister.path,
        repoRoot: repoRoot,
      );
      final violations = [
        for (final diagnostic in result.diagnostics)
          if (!isRosterWideSurfaceUnmatched(diagnostic) &&
              p.normalize(diagnostic.file) == candidatePath)
            '[${diagnostic.ruleId}] ${diagnostic.message}',
      ];
      if (violations.isNotEmpty) {
        throw DecisionRecordException(
          'the new entry does not lint clean: ${violations.join('; ')}',
        );
      }
    } on FileSystemException catch (error) {
      throw DecisionRecordException(error.message);
    } finally {
      if (candidateRoot.existsSync()) {
        candidateRoot.deleteSync(recursive: true);
      }
    }
  }

  DecisionNextStep _nextStep(
    DecisionEdgeKind kind,
    String reference,
    String slug,
    String originRegister,
    List<DecisionEntry> existing,
  ) {
    final qualified = DecisionReference.parse(reference);
    if (qualified == null) {
      final target = existing
          .where(
            (entry) => entry.slug == reference || entry.legacyId == reference,
          )
          .firstOrNull;
      return DecisionNextStep(
        kind: kind,
        target: target?.slug ?? reference,
        successor: slug,
      );
    }
    return DecisionNextStep(
      kind: kind,
      target: _roster.resolveReference(qualified)?.slug ?? qualified.reference,
      successor: '$originRegister#$slug',
      register: qualified.register,
    );
  }
}
