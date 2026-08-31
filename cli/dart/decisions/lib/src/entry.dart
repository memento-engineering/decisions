import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One decision, parsed from a MADR-profile markdown file.
///
/// Only the fields the format REQUIRES are modelled here; the graph layer
/// (edges, force cache, surfaces) lands on top of this in a later cut.
class DecisionEntry {
  /// Creates an entry over its parsed front matter.
  const DecisionEntry({
    required this.file,
    required this.body,
    required this.status,
    required this.date,
    required this.spec,
    required this.slug,
    required this.surfaces,
    required this.obsoletes,
    required this.updates,
    required this.bead,
    required this.legacyId,
    required this.decisionMakers,
  });

  /// The file this entry was parsed from.
  final String file;

  /// The authored MADR Markdown after the YAML front matter.
  final String body;

  /// The MADR status. This profile never uses `proposed`.
  final String status;

  /// The date in the front matter, `YYYY-MM-DD`.
  final String date;

  /// The format version this entry declares.
  final int spec;

  /// The entry's identity, unique within its register.
  final String slug;

  /// Globs or paths this decision governs.
  final List<String> surfaces;

  /// AUTHORED edges: entries this one replaces entirely.
  final List<String> obsoletes;

  /// AUTHORED edges: entries this one amends, which remain in force.
  final List<String> updates;

  /// Optional authored link to the decision-type bead.
  final String? bead;

  /// Optional authored identifier retained from a migrated legacy register.
  final String? legacyId;

  /// MADR's RACI decision-makers.
  final List<String> decisionMakers;

  /// True when the cached status currently says `accepted`.
  ///
  /// This does not account for authored edges; use [DecisionGraph.isBinding]
  /// for graph-derived force.
  bool get isBinding => status == 'accepted';
}

/// Thrown when a file in a register cannot be read as an entry.
class DecisionParseException implements Exception {
  /// Creates the exception for [file] with [message].
  const DecisionParseException(this.file, this.message);

  /// The offending file.
  final String file;

  /// What was wrong with it.
  final String message;

  @override
  String toString() => 'DecisionParseException($file): $message';
}

/// Reads every `*.md` entry in the register rooted at [directory].
///
/// Subdirectories (notably `views/`) are not entries and are skipped.
List<DecisionEntry> readRegister(String directory) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw DecisionParseException(directory, 'no such register directory');
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [for (final f in files) parseEntry(f.path)];
}

/// Parses one entry file.
DecisionEntry parseEntry(String file) {
  final text = File(file).readAsStringSync();
  final match = RegExp(
    r'^---\r?\n(.*?)\r?\n---\r?\n',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) {
    throw DecisionParseException(file, 'no YAML front matter');
  }
  final body = text.substring(match.end).trim();
  if (body.isEmpty) {
    throw DecisionParseException(file, 'empty Markdown body');
  }

  final Object? doc = loadYaml(match.group(1)!);
  if (doc is! YamlMap) {
    throw DecisionParseException(file, 'front matter is not a mapping');
  }
  final Object? register = doc['register'];
  if (register is! YamlMap) {
    throw DecisionParseException(file, 'missing the `register` block');
  }
  final slug = _string(file, register, 'slug');
  final base = p.basenameWithoutExtension(file);
  if (!base.endsWith('-$slug')) {
    throw DecisionParseException(
      file,
      'filename does not end with its slug ($slug)',
    );
  }
  return DecisionEntry(
    file: file,
    body: body,
    status: _string(file, doc, 'status'),
    date: _string(file, doc, 'date'),
    spec: _int(file, register, 'spec'),
    slug: slug,
    surfaces: _stringList(register['surfaces']),
    obsoletes: _stringList(register['obsoletes']),
    updates: _stringList(register['updates']),
    bead: _nullableString(file, register, 'bead'),
    legacyId: _nullableString(file, register, 'legacy-id'),
    decisionMakers: _stringList(doc['decision-makers']),
  );
}

String _string(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value is String && value.isNotEmpty) return value;
  return throw DecisionParseException(file, 'missing or non-string `$key`');
}

String? _nullableString(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw DecisionParseException(file, 'non-string `$key`');
}

int _int(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value is int) return value;
  return throw DecisionParseException(file, 'missing or non-integer `$key`');
}

List<String> _stringList(Object? value) => switch (value) {
  final YamlList list => [for (final Object? e in list) '$e'],
  null => const [],
  _ => const [],
};
