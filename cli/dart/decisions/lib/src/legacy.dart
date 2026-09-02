import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One ratified legacy ADR selected explicitly for whole-document conversion.
final class LegacyRatifiedAdr {
  /// Creates a ratified source at [file] with its original decision [date].
  const LegacyRatifiedAdr({required this.file, required this.date});

  /// The authored legacy Markdown file.
  final String file;

  /// The original decision date used by the converted entry.
  final String date;
}

/// The files emitted by one legacy-register conversion.
final class LegacyConversionResult {
  /// Creates an immutable conversion result from [files].
  LegacyConversionResult(Iterable<String> files)
    : files = List<String>.unmodifiable(files);

  /// Emitted entry files, sorted by filename.
  final List<String> files;
}

/// Thrown when a legacy register cannot be converted mechanically and safely.
class LegacyConversionException implements Exception {
  /// Creates a conversion failure with [message].
  const LegacyConversionException(this.message);

  /// What prevented conversion.
  final String message;

  @override
  String toString() => 'LegacyConversionException: $message';
}

/// Reads the verbatim `[start, end)` span of a register for one heading.
typedef LegacyBodyReader = String Function(String text, int start, int end);

/// Thrown when a converted body would not be byte-identical to its source span.
///
/// The conversion contract (`decisions#legacy-register-migration`) is that a
/// body is copied verbatim. A body that fails that check is refused by name
/// rather than emitted, because a wrong output lints clean.
final class LegacyRegisterRefused extends LegacyConversionException {
  /// Refuses [file] because the body under [heading] is not verbatim.
  LegacyRegisterRefused({required this.file, required this.heading})
    : super(
        'refusing "$file": the body under heading "$heading" is not '
        'byte-identical to its heading-to-next-heading span',
      );

  /// The legacy register that was refused.
  final String file;

  /// The exact heading line whose body failed the byte-identity check.
  final String heading;

  @override
  String toString() => 'LegacyRegisterRefused: $message';
}

/// UI-drivable contract for converting one legacy register.
abstract interface class LegacyRegisterConverter {
  /// Converts [registerFile] and explicit [ratifiedAdrs] into [outputDirectory].
  LegacyConversionResult convert({
    required String registerFile,
    required Iterable<LegacyRatifiedAdr> ratifiedAdrs,
    required Iterable<String> surfaces,
    required String human,
    required String outputDirectory,
  });
}

/// Mechanical Option-C conversion with verbatim bodies and empty edges.
final class LegacyRegisterConversionService implements LegacyRegisterConverter {
  /// Creates the stateless conversion service.
  ///
  /// [readBody] is the single injected seam. Production always takes the
  /// default verbatim reader; a test passes a non-verbatim Fake so the
  /// byte-identity refusal in `_readSections` has a reachable failure path.
  const LegacyRegisterConversionService({
    LegacyBodyReader readBody = _verbatimBody,
  }) : _readBody = readBody;

  final LegacyBodyReader _readBody;

  static final _amendmentHeading = RegExp(
    r'^## (A[1-9][0-9]*) \((\d{4}-\d{2}-\d{2})\) — ([^\r\n]+)$',
  );
  static final _amendmentCandidate = RegExp(r'^## A[0-9]+');
  static final _headingDate = RegExp(r'\((\d{4}-\d{2}-\d{2})[^)]*\)');
  static final _ratifiedFile = RegExp(r'^(?:ADR-)?([0-9]{4})-(.+)\.md$');
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static String _verbatimBody(String text, int start, int end) =>
      text.substring(start, end);

  @override
  LegacyConversionResult convert({
    required String registerFile,
    required Iterable<LegacyRatifiedAdr> ratifiedAdrs,
    required Iterable<String> surfaces,
    required String human,
    required String outputDirectory,
  }) {
    final surfaceList = List<String>.unmodifiable(surfaces);
    final ratifiedList = List<LegacyRatifiedAdr>.unmodifiable(ratifiedAdrs);
    _validateInvocation(
      surfaces: surfaceList,
      human: human,
      outputDirectory: outputDirectory,
    );

    final sources = <_LegacySource>[
      ..._readSections(registerFile, human: human),
      for (final ratified in ratifiedList)
        _readRatified(ratified, human: human),
    ];
    final legacyIds = <String>{};
    for (final source in sources) {
      final legacyId = source.legacyId;
      if (legacyId == null) continue;
      if (!legacyIds.add(legacyId)) {
        throw LegacyConversionException('duplicate legacy id "$legacyId"');
      }
    }

    final planned = <_PlannedEntry>[
      for (final source in sources)
        _PlannedEntry(
          file: p.join(outputDirectory, '${source.date}-${source.slug}.md'),
          content: _renderEntry(source, surfaceList),
        ),
    ]..sort((left, right) => left.file.compareTo(right.file));
    final names = <String>{};
    for (final entry in planned) {
      final name = p.basename(entry.file);
      if (!names.add(name)) {
        throw LegacyConversionException('duplicate output filename "$name"');
      }
      if (File(entry.file).existsSync()) {
        throw LegacyConversionException(
          'refusing to overwrite existing output "${entry.file}"',
        );
      }
    }

    Directory(outputDirectory).createSync(recursive: true);
    for (final entry in planned) {
      File(entry.file).writeAsStringSync(entry.content, flush: true);
    }
    return LegacyConversionResult(planned.map((entry) => entry.file));
  }

  static void _validateInvocation({
    required List<String> surfaces,
    required String human,
    required String outputDirectory,
  }) {
    if (surfaces.isEmpty) {
      throw const LegacyConversionException(
        'at least one authored surface is required',
      );
    }
    for (final surface in surfaces) {
      if (surface.isEmpty || surface.trim() != surface) {
        throw LegacyConversionException('invalid surface "$surface"');
      }
    }
    if (human.isEmpty || human.trim() != human) {
      throw const LegacyConversionException(
        'the ratifying human must be a non-blank exact value',
      );
    }
    if (outputDirectory.isEmpty || outputDirectory.trim() != outputDirectory) {
      throw const LegacyConversionException(
        'the output directory must be a non-blank exact path',
      );
    }
  }

  static List<_Heading> _headings(String text) {
    final result = <_Heading>[];
    var fenced = false;
    var offset = 0;
    while (true) {
      final newline = text.indexOf('\n', offset);
      final end = newline == -1 ? text.length : newline;
      var line = text.substring(offset, end);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.startsWith('```') || line.startsWith('~~~')) {
        fenced = !fenced;
      } else if (!fenced && line.startsWith('## ')) {
        result.add(
          _Heading(start: offset, line: line, text: line.substring(3)),
        );
      }
      if (newline == -1) break;
      offset = newline + 1;
    }
    return List<_Heading>.unmodifiable(result);
  }

  List<_LegacySource> _readSections(String file, {required String human}) {
    final text = _readText(file);
    final headings = _headings(text);
    final ids = <String>{};
    final result = <_LegacySource>[];
    var previousDate = '';
    for (var index = 0; index < headings.length; index++) {
      final heading = headings[index];
      final end = index + 1 == headings.length
          ? text.length
          : headings[index + 1].start;
      final body = _readBody(text, heading.start, end);
      if (body != text.substring(heading.start, end)) {
        throw LegacyRegisterRefused(file: file, heading: heading.line);
      }
      final amendment = _amendmentHeading.firstMatch(heading.line);
      if (amendment == null) {
        if (_amendmentCandidate.hasMatch(heading.line)) {
          throw LegacyConversionException(
            'malformed amendment heading in "$file": "${heading.line}"',
          );
        }
        final date =
            _headingDate.firstMatch(heading.text)?.group(1) ?? previousDate;
        if (date.isEmpty) {
          throw LegacyConversionException(
            'section heading "${heading.line}" in "$file" carries no '
            '(YYYY-MM-DD ...) parenthetical and follows no dated section',
          );
        }
        _requireDate(date, source: '$file ${heading.line}');
        final slug = _slug('', heading.text.replaceFirst(_headingDate, ' '));
        if (slug.isEmpty) {
          throw LegacyConversionException(
            'section heading "${heading.line}" in "$file" yields an empty slug',
          );
        }
        result.add(
          _LegacySource(
            date: date,
            slug: slug,
            legacyId: null,
            decisionMaker: _namesHuman(heading.text, human) ? human : 'agent',
            body: body,
          ),
        );
        previousDate = date;
        continue;
      }
      final legacyId = amendment.group(1)!;
      final date = amendment.group(2)!;
      final title = amendment.group(3)!;
      if (!ids.add(legacyId)) {
        throw LegacyConversionException(
          'duplicate amendment id "$legacyId" in "$file"',
        );
      }
      _requireDate(date, source: '$file $legacyId');
      result.add(
        _LegacySource(
          date: date,
          slug: _slug(legacyId.toLowerCase(), title),
          legacyId: legacyId,
          decisionMaker: 'agent',
          body: body,
        ),
      );
      previousDate = date;
    }
    if (ids.isEmpty) {
      throw LegacyConversionException(
        'legacy register "$file" contains no amendment headings',
      );
    }
    return List<_LegacySource>.unmodifiable(result);
  }

  static bool _namesHuman(String heading, String human) =>
      heading.contains('RATIFIED') ||
      heading.contains('Ratified') ||
      heading.toLowerCase().contains(human.toLowerCase());

  static _LegacySource _readRatified(
    LegacyRatifiedAdr ratified, {
    required String human,
  }) {
    final name = p.basename(ratified.file);
    final match = _ratifiedFile.firstMatch(name);
    if (match == null || match.group(1) == '0000') {
      throw LegacyConversionException(
        'ratified ADR filename "$name" must be ADR-000N-title.md or '
        '000N-title.md, excluding 0000',
      );
    }
    _requireDate(ratified.date, source: ratified.file);
    final number = match.group(1)!;
    final title = match.group(2)!;
    return _LegacySource(
      date: ratified.date,
      slug: _slug('adr-$number', title),
      legacyId: 'ADR-$number',
      decisionMaker: human,
      body: _readText(ratified.file),
    );
  }

  static String _readText(String file) {
    try {
      return File(file).readAsStringSync();
    } on FileSystemException catch (error) {
      throw LegacyConversionException('cannot read "$file": ${error.message}');
    }
  }

  static void _requireDate(String value, {required String source}) {
    if (!_date.hasMatch(value)) {
      throw LegacyConversionException('invalid date "$value" for "$source"');
    }
    final parts = value.split('-').map(int.parse).toList(growable: false);
    final parsed = DateTime.tryParse(value);
    if (parsed == null ||
        parsed.year != parts[0] ||
        parsed.month != parts[1] ||
        parsed.day != parts[2]) {
      throw LegacyConversionException('invalid date "$value" for "$source"');
    }
  }

  static String _slug(String prefix, String title) {
    final titleSlug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final value = [
      if (prefix.isNotEmpty) prefix,
      if (titleSlug.isNotEmpty) titleSlug,
    ].join('-');
    final shortened = value.length <= 60 ? value : value.substring(0, 60);
    return shortened.replaceFirst(RegExp(r'-+$'), '');
  }

  static String _renderEntry(_LegacySource source, List<String> surfaces) {
    final surfaceYaml = surfaces
        .map((surface) => '    - ${jsonEncode(surface)}')
        .join('\n');
    return '''---
status: accepted
date: ${source.date}
decision-makers: [${jsonEncode(source.decisionMaker)}]
consulted: []
informed: []
register:
  spec: 1
  slug: ${source.slug}
  surfaces:
$surfaceYaml
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: ${jsonEncode(source.legacyId)}
---
${source.body}''';
  }
}

final class _LegacySource {
  const _LegacySource({
    required this.date,
    required this.slug,
    required this.legacyId,
    required this.decisionMaker,
    required this.body,
  });

  final String date;
  final String slug;
  final String? legacyId;
  final String decisionMaker;
  final String body;
}

final class _Heading {
  const _Heading({required this.start, required this.line, required this.text});

  final int start;
  final String line;
  final String text;
}

final class _PlannedEntry {
  const _PlannedEntry({required this.file, required this.content});

  final String file;
  final String content;
}
