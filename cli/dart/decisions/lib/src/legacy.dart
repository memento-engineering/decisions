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
  const LegacyRegisterConversionService();

  static final _amendmentHeading = RegExp(
    r'^## (A[1-9][0-9]*) \((\d{4}-\d{2}-\d{2})\) — ([^\r\n]+)\r?$',
    multiLine: true,
  );
  static final _amendmentCandidate = RegExp(
    r'^## A[0-9]+[^\r\n]*\r?$',
    multiLine: true,
  );
  static final _ratifiedFile = RegExp(r'^(?:ADR-)?([0-9]{4})-(.+)\.md$');
  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

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
      ..._readAmendments(registerFile),
      for (final ratified in ratifiedList)
        _readRatified(ratified, human: human),
    ];
    final legacyIds = <String>{};
    for (final source in sources) {
      if (!legacyIds.add(source.legacyId)) {
        throw LegacyConversionException(
          'duplicate legacy id "${source.legacyId}"',
        );
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

  static List<_LegacySource> _readAmendments(String file) {
    final text = _readText(file);
    final matches = _amendmentHeading.allMatches(text).toList(growable: false);
    final candidates = _amendmentCandidate
        .allMatches(text)
        .toList(growable: false);
    if (matches.isEmpty) {
      throw LegacyConversionException(
        'legacy register "$file" contains no amendment headings',
      );
    }
    final exactOffsets = matches.map((match) => match.start).toSet();
    final malformed = candidates.where(
      (candidate) => !exactOffsets.contains(candidate.start),
    );
    if (malformed.isNotEmpty) {
      throw LegacyConversionException(
        'malformed amendment heading in "$file" at byte-like offset '
        '${malformed.first.start}',
      );
    }

    final ids = <String>{};
    final result = <_LegacySource>[];
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final legacyId = match.group(1)!;
      final date = match.group(2)!;
      final title = match.group(3)!;
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
          body: text.substring(
            match.start,
            index + 1 == matches.length
                ? text.length
                : matches[index + 1].start,
          ),
        ),
      );
    }
    return List<_LegacySource>.unmodifiable(result);
  }

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
    final value = titleSlug.isEmpty ? prefix : '$prefix-$titleSlug';
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
  final String legacyId;
  final String decisionMaker;
  final String body;
}

final class _PlannedEntry {
  const _PlannedEntry({required this.file, required this.content});

  final String file;
  final String content;
}
