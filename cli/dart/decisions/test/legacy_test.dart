import 'dart:convert';
import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixture = 'test/fixtures/legacy_register';
const _registerRelative = 'docs/adr/ADR-0000-ai-decision-register.md';
const _ratifiedRelative = 'docs/adr/ADR-0001-technical-foundations.md';
const _outputRelative = 'docs/decisions';
const _service = LegacyRegisterConversionService();

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('decisions-legacy-');
    _copyFixture(Directory(_fixture), root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test(
    'amendments convert one-for-one with byte-identical bodies and empty edges',
    () {
      final result = _convert(root, includeRatified: false);
      final output = p.join(root.path, _outputRelative);
      final entries = readRegister(output);
      final sourceBodies = _amendmentBodies(
        p.join(root.path, _registerRelative),
      );

      expect(result.files, hasLength(3));
      expect(entries, hasLength(3));
      for (final entry in entries) {
        expect(entry.spec, 1);
        expect(entry.status, 'accepted');
        expect(entry.decisionMakers, ['agent']);
        expect(entry.obsoletes, isEmpty);
        expect(entry.updates, isEmpty);
        expect(entry.cachedObsoletedBy, isNull);
        expect(entry.cachedUpdatedBy, isEmpty);
        expect(
          _bodyBytes(File(entry.file).readAsBytesSync()),
          orderedEquals(sourceBodies[entry.legacyId]!),
        );
      }

      final graph = DecisionGraph(entries);
      expect(graph.edges, isEmpty);
      expect(graph.pendingEdges, isEmpty);
      expect(graph.entry('A25').body, contains('RE-HOMING pending A10'));
    },
  );

  test('ratified ADR converts whole with human authorship', () {
    final result = _convert(root);
    final entries = readRegister(p.join(root.path, _outputRelative));
    final graph = DecisionGraph(entries);
    final ratified = graph.entry('ADR-0001');

    expect(result.files, hasLength(4));
    expect(ratified.decisionMakers, ['Nico Spencer']);
    expect(ratified.status, 'accepted');
    expect(ratified.obsoletes, isEmpty);
    expect(ratified.updates, isEmpty);
    expect(
      RegExp(r'^## Decision [0-9]+', multiLine: true).allMatches(ratified.body),
      hasLength(10),
    );
    expect(
      _bodyBytes(File(ratified.file).readAsBytesSync()),
      orderedEquals(
        File(p.join(root.path, _ratifiedRelative)).readAsBytesSync(),
      ),
    );
  });

  test(
    'legacy ids resolve and converted output lints with supplied surfaces',
    () {
      _convert(root);
      final output = p.join(root.path, _outputRelative);
      final entries = readRegister(output);
      final graph = DecisionGraph(entries);

      for (final entry in entries) {
        expect(entry.surfaces, ['docs/adr/**']);
        expect(graph.entry(entry.legacyId!), same(entry));
      }
      final lint = const DecisionLintService().lint(
        registerPath: output,
        repoRoot: root.path,
      );
      expect(lint.isClean, isTrue, reason: '${lint.toJson()}');
      expect(lint.diagnostics, isEmpty);
    },
  );

  test('malformed input and output collisions fail loudly without writes', () {
    final emptySurfaceOutput = p.join(root.path, 'empty-surface-output');
    expect(
      () => _service.convert(
        registerFile: p.join(root.path, _registerRelative),
        ratifiedAdrs: const [],
        surfaces: const [],
        human: 'Nico Spencer',
        outputDirectory: emptySurfaceOutput,
      ),
      throwsA(isA<LegacyConversionException>()),
    );
    expect(Directory(emptySurfaceOutput).existsSync(), isFalse);

    final malformed = File(p.join(root.path, 'malformed-register.md'))
      ..writeAsStringSync('## A0 (2026-08-31) - missing em dash\n\nBody\n');
    final malformedOutput = p.join(root.path, 'malformed-output');
    expect(
      () => _service.convert(
        registerFile: malformed.path,
        ratifiedAdrs: const [],
        surfaces: const ['docs/adr/**'],
        human: 'Nico Spencer',
        outputDirectory: malformedOutput,
      ),
      throwsA(isA<LegacyConversionException>()),
    );
    expect(Directory(malformedOutput).existsSync(), isFalse);

    final converted = _convert(root);
    final before = {
      for (final file in converted.files) file: File(file).readAsBytesSync(),
    };
    expect(() => _convert(root), throwsA(isA<LegacyConversionException>()));
    for (final MapEntry(key: file, value: bytes) in before.entries) {
      expect(File(file).readAsBytesSync(), orderedEquals(bytes));
    }
  });
}

LegacyConversionResult _convert(
  Directory root, {
  bool includeRatified = true,
}) => _service.convert(
  registerFile: p.join(root.path, _registerRelative),
  ratifiedAdrs: [
    if (includeRatified)
      LegacyRatifiedAdr(
        file: p.join(root.path, _ratifiedRelative),
        date: '2026-06-11',
      ),
  ],
  surfaces: const ['docs/adr/**'],
  human: 'Nico Spencer',
  outputDirectory: p.join(root.path, _outputRelative),
);

void _copyFixture(Directory source, Directory target) {
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final destination = File(
      p.join(target.path, p.relative(entity.path, from: source.path)),
    );
    destination.parent.createSync(recursive: true);
    destination.writeAsBytesSync(entity.readAsBytesSync());
  }
}

Map<String, List<int>> _amendmentBodies(String file) {
  final text = File(file).readAsStringSync();
  final matches = RegExp(
    r'^## (A[1-9][0-9]*) \(\d{4}-\d{2}-\d{2}\) — [^\r\n]+\r?$',
    multiLine: true,
  ).allMatches(text).toList(growable: false);
  return {
    for (var index = 0; index < matches.length; index++)
      matches[index].group(1)!: utf8.encode(
        text.substring(
          matches[index].start,
          index + 1 == matches.length ? text.length : matches[index + 1].start,
        ),
      ),
  };
}

List<int> _bodyBytes(List<int> entryBytes) {
  const marker = <int>[10, 45, 45, 45, 10];
  for (var index = 4; index <= entryBytes.length - marker.length; index++) {
    var found = true;
    for (var offset = 0; offset < marker.length; offset++) {
      if (entryBytes[index + offset] != marker[offset]) {
        found = false;
        break;
      }
    }
    if (found) return entryBytes.sublist(index + marker.length);
  }
  throw StateError('entry has no closing front-matter delimiter');
}
