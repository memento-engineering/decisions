import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The structured reason an entry could not be parsed.
enum DecisionParseFailure {
  /// Front matter does not satisfy the spec-1 schema shape.
  schema,

  /// The date and slug do not exactly form the markdown filename.
  filename,
}

/// One decision, parsed from a MADR-profile markdown file.
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
    required this.cachedObsoletedBy,
    required this.cachedUpdatedBy,
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

  /// Cached source slug that obsoletes this entry, or null.
  final String? cachedObsoletedBy;

  /// Cached source slugs that update this entry.
  final List<String> cachedUpdatedBy;

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
  /// Creates an exception for [file] with a structured [failure].
  const DecisionParseException(
    this.file,
    this.message, {
    this.failure = DecisionParseFailure.schema,
  });

  /// The offending file.
  final String file;

  /// What was wrong with it.
  final String message;

  /// The structured reason parsing failed.
  final DecisionParseFailure failure;

  @override
  String toString() => 'DecisionParseException($file): $message';
}

const _registerKeys = <String>{
  'spec',
  'slug',
  'surfaces',
  'obsoletes',
  'updates',
  'obsoleted-by',
  'updated-by',
  'bead',
  'legacy-id',
};
final _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
final _supersededStatusPattern = RegExp(
  r'^superseded by [a-z0-9]+(?:-[a-z0-9]+)*$',
);

/// Reads every `*.md` entry in the register rooted at [directory].
///
/// Subdirectories (notably `views/`) are not entries and are skipped. When
/// [onParseError] is absent, the first malformed entry is thrown exactly as
/// before. When supplied, each [DecisionParseException] is reported and the
/// remaining files are parsed.
List<DecisionEntry> readRegister(
  String directory, {
  void Function(DecisionParseException error)? onParseError,
}) {
  final dir = Directory(directory);
  if (!dir.existsSync()) {
    throw DecisionParseException(directory, 'no such register directory');
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  final entries = <DecisionEntry>[];
  for (final file in files) {
    try {
      entries.add(parseEntry(file.path));
    } on DecisionParseException catch (error) {
      final handler = onParseError;
      if (handler == null) rethrow;
      handler(error);
    }
  }
  return entries;
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

  final Object? document = loadYaml(match.group(1)!);
  if (document is! YamlMap) {
    throw DecisionParseException(file, 'front matter is not a mapping');
  }
  final Object? registerValue = document['register'];
  if (registerValue is! YamlMap) {
    throw DecisionParseException(file, 'missing the `register` block');
  }
  final unknownKeys =
      registerValue.keys
          .map((key) => '$key')
          .where((key) => !_registerKeys.contains(key))
          .toList()
        ..sort();
  if (unknownKeys.isNotEmpty) {
    throw DecisionParseException(
      file,
      'unknown register keys: ${unknownKeys.join(', ')}',
    );
  }

  final status = _string(file, document, 'status');
  if (status != 'accepted' &&
      status != 'deprecated' &&
      status != 'rejected' &&
      status != 'proposed' &&
      !_supersededStatusPattern.hasMatch(status)) {
    throw DecisionParseException(file, 'unsupported `status` value');
  }
  final date = _string(file, document, 'date');
  if (!_isValidDate(date)) {
    throw DecisionParseException(file, 'invalid `date`');
  }

  final spec = _int(file, registerValue, 'spec');
  if (spec < 1) {
    throw DecisionParseException(file, '`spec` must be at least 1');
  }
  final slug = _string(file, registerValue, 'slug');
  if (slug.length > 80 || !_slugPattern.hasMatch(slug)) {
    throw DecisionParseException(file, 'invalid `slug`');
  }
  final expectedName = '$date-$slug.md';
  if (p.basename(file) != expectedName) {
    throw DecisionParseException(
      file,
      'expected filename "$expectedName"',
      failure: DecisionParseFailure.filename,
    );
  }

  return DecisionEntry(
    file: file,
    body: body,
    status: status,
    date: date,
    spec: spec,
    slug: slug,
    surfaces: _stringList(
      file,
      registerValue,
      'surfaces',
      required: true,
      nonEmpty: true,
    ),
    obsoletes: _stringList(file, registerValue, 'obsoletes'),
    updates: _stringList(file, registerValue, 'updates'),
    cachedObsoletedBy: _nullableString(file, registerValue, 'obsoleted-by'),
    cachedUpdatedBy: _stringList(file, registerValue, 'updated-by'),
    bead: _nullableString(file, registerValue, 'bead'),
    legacyId: _nullableString(file, registerValue, 'legacy-id'),
    decisionMakers: _stringList(file, document, 'decision-makers'),
  );
}

bool _isValidDate(String value) {
  if (!_datePattern.hasMatch(value)) return false;
  final parts = value.split('-').map(int.parse).toList();
  final parsed = DateTime.tryParse(value);
  return parsed != null &&
      parsed.year == parts[0] &&
      parsed.month == parts[1] &&
      parsed.day == parts[2];
}

String _string(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value is String && value.isNotEmpty) return value;
  return throw DecisionParseException(file, 'missing or non-string `$key`');
}

String? _nullableString(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value == null) return null;
  if (value is String) return value;
  throw DecisionParseException(file, 'non-string `$key`');
}

int _int(String file, YamlMap map, String key) {
  final Object? value = map[key];
  if (value is int) return value;
  return throw DecisionParseException(file, 'missing or non-integer `$key`');
}

List<String> _stringList(
  String file,
  YamlMap map,
  String key, {
  bool required = false,
  bool nonEmpty = false,
}) {
  final Object? value = map[key];
  if (value == null && !required) return const [];
  if (value is! YamlList || (nonEmpty && value.isEmpty)) {
    throw DecisionParseException(file, 'missing or non-array `$key`');
  }
  final result = <String>[];
  for (final Object? item in value) {
    if (item is! String) {
      throw DecisionParseException(file, 'non-string item in `$key`');
    }
    result.add(item);
  }
  return List<String>.unmodifiable(result);
}
