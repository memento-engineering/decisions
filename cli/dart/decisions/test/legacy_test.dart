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
const _powerStationEnv = 'DECISIONS_POWER_STATION_ROOT';
const _powerStationRatified = <String, String>{
  'ADR-0001-packaged-ai-asset-skill-command-coupling.md': '2026-07-20',
  'ADR-0002-agent-environment-layer.md': '2026-07-14',
  'ADR-0003-private-git-tag-releases-and-prerelease-gate.md': '2026-07-15',
  'ADR-0004-station-throughput-outranks-staging-ceremony.md': '2026-08-12',
  'ADR-0005-landing-policy-grade-gated-auto-merge.md': '2026-08-23',
  'ADR-0006-typed-environment-lookup-selects-by-value.md': '2026-09-01',
};

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
    'every heading converts one-for-one with byte-identical bodies and empty edges',
    () {
      final result = _convert(root, includeRatified: false);
      final output = p.join(root.path, _outputRelative);
      final entries = readRegister(output);
      final sourceBodies = _sectionBodies(p.join(root.path, _registerRelative));

      expect(result.files, hasLength(4));
      expect(entries, hasLength(4));
      for (final entry in entries) {
        expect(entry.spec, 1);
        expect(entry.status, 'accepted');
        expect(
          entry.decisionMakers,
          entry.legacyId == null ? ['Nico Spencer'] : ['agent'],
        );
        expect(entry.obsoletes, isEmpty);
        expect(entry.updates, isEmpty);
        expect(entry.cachedObsoletedBy, isNull);
        expect(entry.cachedUpdatedBy, isEmpty);
        expect(
          _bodyBytes(File(entry.file).readAsBytesSync()),
          orderedEquals(sourceBodies[entry.body.split('\n').first]!),
        );
      }

      final section = entries.singleWhere((entry) => entry.legacyId == null);
      expect(section.date, '2026-08-20');
      expect(section.slug, 'ratified-split-on-every-heading');
      expect(section.decisionMakers, ['Nico Spencer']);
      expect(
        section.body,
        startsWith('## RATIFIED — SPLIT ON EVERY HEADING (2026-08-20, '),
      );
      expect(section.body, isNot(contains('A32')));
      expect(
        p.basename(section.file),
        '2026-08-20-ratified-split-on-every-heading.md',
      );
      expect(
        DecisionGraph(entries).entry('A25').body,
        isNot(contains('SPLIT ON EVERY HEADING')),
      );

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

    expect(result.files, hasLength(5));
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

      expect(entries.where((entry) => entry.legacyId == null), hasLength(1));
      for (final entry in entries) {
        expect(entry.surfaces, ['docs/adr/**']);
        if (entry.legacyId case final legacyId?) {
          expect(graph.entry(legacyId), same(entry));
        }
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

  test('a non-verbatim body is refused loudly, naming its heading', () {
    final control = _convert(root, includeRatified: false);
    expect(control.files, hasLength(4));

    const mangling = LegacyRegisterConversionService(readBody: _appendSpace);
    final refusedOutput = p.join(root.path, 'refused-output');
    expect(
      () => mangling.convert(
        registerFile: p.join(root.path, _registerRelative),
        ratifiedAdrs: const [],
        surfaces: const ['docs/adr/**'],
        human: 'Nico Spencer',
        outputDirectory: refusedOutput,
      ),
      throwsA(
        isA<LegacyRegisterRefused>().having(
          (error) => error.heading,
          'heading',
          '## A1 (2026-07-02) — Provision-time linkage stays in '
              'AgentCapability.spawn',
        ),
      ),
    );
    expect(Directory(refusedOutput).existsSync(), isFalse);
  });

  test(
    'a dateless section inherits the previous date; a leading one is refused',
    () {
      final inherit = File(p.join(root.path, 'inherit-register.md'))
        ..writeAsStringSync(
          '## A1 (2026-07-02) — First\n\nBody.\n\n'
          '## RATIFIED — no parenthetical here\n\nNico ruled.\n',
        );
      final inheritOutput = p.join(root.path, 'inherit-output');
      _service.convert(
        registerFile: inherit.path,
        ratifiedAdrs: const [],
        surfaces: const ['docs/adr/**'],
        human: 'Nico Spencer',
        outputDirectory: inheritOutput,
      );
      final inherited = readRegister(
        inheritOutput,
      ).singleWhere((entry) => entry.legacyId == null);
      expect(inherited.date, '2026-07-02');
      expect(inherited.slug, 'ratified-no-parenthetical-here');
      expect(inherited.decisionMakers, ['Nico Spencer']);

      final leading = File(p.join(root.path, 'leading-register.md'))
        ..writeAsStringSync(
          '## RATIFIED — no date at all\n\nNico ruled.\n\n'
          '## A1 (2026-07-02) — First\n\nBody.\n',
        );
      final leadingOutput = p.join(root.path, 'leading-output');
      expect(
        () => _service.convert(
          registerFile: leading.path,
          ratifiedAdrs: const [],
          surfaces: const ['docs/adr/**'],
          human: 'Nico Spencer',
          outputDirectory: leadingOutput,
        ),
        throwsA(isA<LegacyConversionException>()),
      );
      expect(Directory(leadingOutput).existsSync(), isFalse);
    },
  );

  test(
    'power_station converts to its landed migrated tree',
    () {
      final source = Platform.environment[_powerStationEnv]!;
      final output = Directory.systemTemp.createTempSync('decisions-power-');
      addTearDown(() => output.deleteSync(recursive: true));
      final emitted = _service.convert(
        registerFile: p.join(
          source,
          'docs',
          'adr',
          'ADR-0000-ai-decision-register.md',
        ),
        ratifiedAdrs: [
          for (final MapEntry(key: file, value: date)
              in _powerStationRatified.entries)
            LegacyRatifiedAdr(
              file: p.join(source, 'docs', 'adr', file),
              date: date,
            ),
        ],
        surfaces: const ['packages/**'],
        human: 'nico',
        outputDirectory: p.join(output.path, 'decisions'),
      );

      final landed = Directory(p.join(source, 'docs', 'decisions'))
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList(growable: false);
      expect(emitted.files, hasLength(46));
      expect(landed, hasLength(46));
      expect({
        for (final file in emitted.files) _entryBody(File(file)),
      }, equals({for (final file in landed) _entryBody(file)}));

      final landedByName = {
        for (final file in landed) p.basename(file.path): file,
      };
      final emittedNames = emitted.files.map(p.basename).toSet();
      for (final file in emitted.files) {
        final match = landedByName[p.basename(file)];
        if (match == null) continue;
        expect(
          File(file).readAsStringSync(),
          match.readAsStringSync(),
          reason: p.basename(file),
        );
      }
      expect(landedByName.keys.toSet().difference(emittedNames), {
        '2026-07-14-ratified-discovery-gate-pending-amendments-advisory.md',
        '2026-07-14-ratified-skills-home-cross-amendment-rule.md',
      });
      final onlyEmitted = emittedNames.difference(landedByName.keys.toSet());
      expect(onlyEmitted, hasLength(2));
      expect(onlyEmitted, everyElement(startsWith('2026-07-14-ratified-')));
    },
    skip: Platform.environment[_powerStationEnv] == null
        ? 'set $_powerStationEnv to a power_station checkout to run the '
              'migrated-tree reproduction'
        : null,
  );
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

Map<String, List<int>> _sectionBodies(String file) {
  final text = File(file).readAsStringSync();
  final matches = RegExp(
    r'^## [^\r\n]*',
    multiLine: true,
  ).allMatches(text).toList(growable: false);
  return {
    for (var index = 0; index < matches.length; index++)
      matches[index].group(0)!: utf8.encode(
        text.substring(
          matches[index].start,
          index + 1 == matches.length ? text.length : matches[index + 1].start,
        ),
      ),
  };
}

/// A deliberately non-verbatim reader — the Fake that arms the refusal guard.
String _appendSpace(String text, int start, int end) =>
    '${text.substring(start, end)} ';

String _entryBody(File file) {
  final text = file.readAsStringSync();
  final end = text.indexOf('\n---\n', 4);
  if (end == -1) {
    throw StateError('entry has no closing front-matter delimiter');
  }
  return text.substring(end + 5);
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
