import 'dart:convert';
import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _selfHostedRegister = '../../../docs/decisions';
const _fixtureRegister = 'test/fixtures/graph_register';
const _templateFile = '../../../templates/view.md';

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decisions-render-');
  });

  tearDown(() {
    sandbox.deleteSync(recursive: true);
  });

  test('self-hosted render anchors every binding decision', () {
    _expectAnchorsEveryBinding(
      _selfHostedRegister,
      p.join(sandbox.path, 'views'),
    );
  });

  test('a new entry with no bead and no edge renders as one more view', () {
    final register = Directory(p.join(sandbox.path, 'register'))..createSync();
    for (final file in Directory(
      _selfHostedRegister,
    ).listSync().whereType<File>()) {
      file.copySync(p.join(register.path, p.basename(file.path)));
    }
    _writeTemporaryEntry(register.path);
    final original = renderViews(
      graph: DecisionGraph(readRegister(_selfHostedRegister)),
      template: File(_templateFile).readAsStringSync(),
    );

    final views = _expectAnchorsEveryBinding(
      register.path,
      p.join(sandbox.path, 'copy-views'),
    );

    expect(views, hasLength(original.length + 1));
    expect(
      views
          .where((view) => view.fileName.endsWith('-$_temporarySlug.md'))
          .length,
      1,
    );
  });

  test('superseded entry names and links its successor', () {
    final graph = DecisionGraph(readRegister(_fixtureRegister));
    final template = File(_templateFile).readAsStringSync();
    final view = renderViews(graph: graph, template: template).single;

    expect(view.content, contains('<a id="amendment"></a>'));
    expect(
      view.content,
      contains('**Superseded by:** [`replacement`](#replacement)'),
    );
  });

  test('unchanged register renders byte-identically twice', () {
    final output = Directory(p.join(sandbox.path, 'views'));
    final first = renderRegister(
      registerDirectory: _selfHostedRegister,
      templateFile: _templateFile,
      outputDirectory: output.path,
    );
    final before = _markdownBytes(output);
    final placeholder = File(p.join(output.path, '.PLACEHOLDER'))
      ..writeAsStringSync('preserve me\n');
    final stale = File(p.join(output.path, '9999-stale.md'))
      ..writeAsStringSync('stale\n');

    final second = renderRegister(
      registerDirectory: _selfHostedRegister,
      templateFile: _templateFile,
      outputDirectory: output.path,
    );
    final after = _markdownBytes(output);

    expect(
      second.map((view) => view.fileName),
      first.map((view) => view.fileName),
    );
    expect(after, equals(before));
    expect(stale.existsSync(), isFalse);
    expect(placeholder.readAsStringSync(), 'preserve me\n');
  });

  test('uses the supplied template as the complete layout', () {
    final graph = DecisionGraph(readRegister(_selfHostedRegister));
    final template = File(_templateFile).readAsStringSync().replaceFirst(
      '<!-- GENERATED',
      '<!-- layout sentinel -->\n<!-- GENERATED',
    );
    final views = renderViews(graph: graph, template: template);

    expect(views, isNotEmpty);
    expect(
      views,
      hasLength(
        renderViews(
          graph: graph,
          template: File(_templateFile).readAsStringSync(),
        ).length,
      ),
    );
    for (final view in views) {
      expect(view.content, startsWith('<!-- layout sentinel -->'));
    }
  });

  test('invalid template fails before replacing generated files', () {
    final output = Directory(p.join(sandbox.path, 'views'))..createSync();
    final existing = File(p.join(output.path, '0001-existing.md'))
      ..writeAsStringSync('keep me\n');
    final invalidTemplate = File(p.join(sandbox.path, 'invalid-view.md'))
      ..writeAsStringSync('{{#entries}}\n{{body}}\n{{/entries}}\n');

    expect(
      () => renderRegister(
        registerDirectory: _selfHostedRegister,
        templateFile: invalidTemplate.path,
        outputDirectory: output.path,
      ),
      throwsA(isA<DecisionRenderException>()),
    );
    expect(existing.readAsStringSync(), 'keep me\n');
  });

  group('decisions render', () {
    test('byte-identical to renderRegister', () async {
      final cliViews = p.join(sandbox.path, 'cli-views');
      final libViews = p.join(sandbox.path, 'lib-views');
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await _run(
        [
          'render',
          _selfHostedRegister,
          '--template',
          _templateFile,
          '--output',
          cliViews,
        ],
        out,
        err,
      );
      final views = renderRegister(
        registerDirectory: _selfHostedRegister,
        templateFile: _templateFile,
        outputDirectory: libViews,
      );

      expect(code, 0);
      final written = _markdownBytes(Directory(cliViews));
      expect(written, isNotEmpty);
      expect(written, equals(_markdownBytes(Directory(libViews))));
      expect(
        out.toString(),
        views.map((view) => '${p.join(cliViews, view.fileName)}\n').join(),
      );
      expect(err.toString(), isEmpty);
    });

    test('missing --template is a usage error', () async {
      final output = p.join(sandbox.path, 'views');
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await _run(
        ['render', _selfHostedRegister, '--output', output],
        out,
        err,
      );

      expect(code, 64);
      expect(err.toString(), contains('render needs --template <file>'));
      expect(Directory(output).existsSync(), isFalse);
    });

    test('wrong positional count is a usage error', () async {
      for (final args in [
        ['render', '--template', _templateFile],
        [
          'render',
          _selfHostedRegister,
          _fixtureRegister,
          '--template',
          _templateFile,
        ],
      ]) {
        final out = StringBuffer();
        final err = StringBuffer();

        expect(await _run(args, out, err), 64, reason: '$args');
        expect(
          err.toString(),
          contains('Expected exactly one register path.'),
          reason: '$args',
        );
      }
    });

    test('invalid template leaves existing views', () async {
      final output = Directory(p.join(sandbox.path, 'views'))..createSync();
      final existing = File(p.join(output.path, '0001-existing.md'))
        ..writeAsStringSync('keep me\n');
      final before = existing.readAsBytesSync();
      final invalidTemplate = File(p.join(sandbox.path, 'invalid-view.md'))
        ..writeAsStringSync('{{#entries}}\n{{body}}\n{{/entries}}\n');
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await _run(
        [
          'render',
          _selfHostedRegister,
          '--template',
          invalidTemplate.path,
          '--output',
          output.path,
        ],
        out,
        err,
      );

      expect(code, 1);
      expect(err.toString(), startsWith('error: '));
      expect(out.toString(), isEmpty);
      expect(existing.readAsBytesSync(), before);
    });

    test('missing register is a refusal', () async {
      final output = p.join(sandbox.path, 'views');
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await _run(
        [
          'render',
          p.join(sandbox.path, 'nowhere'),
          '--template',
          _templateFile,
          '--output',
          output,
        ],
        out,
        err,
      );

      expect(code, 1);
      expect(err.toString(), contains('no such register directory'));
      expect(Directory(output).existsSync(), isFalse);
    });

    test('default output is the register\'s views directory', () async {
      final register = Directory(p.join(sandbox.path, 'register'))
        ..createSync();
      for (final file in Directory(
        _fixtureRegister,
      ).listSync().whereType<File>()) {
        file.copySync(p.join(register.path, p.basename(file.path)));
      }
      final out = StringBuffer();
      final err = StringBuffer();

      final code = await _run(
        ['render', register.path, '--template', _templateFile],
        out,
        err,
      );
      final views = renderViews(
        graph: DecisionGraph(readRegister(register.path)),
        template: File(_templateFile).readAsStringSync(),
      );

      expect(code, 0);
      expect(views, isNotEmpty);
      expect(
        _markdownBytes(Directory(p.join(register.path, 'views'))),
        equals({
          for (final view in views) view.fileName: utf8.encode(view.content),
        }),
      );
      expect(
        out.toString(),
        views
            .map((view) => '${p.join(register.path, 'views', view.fileName)}\n')
            .join(),
      );
      expect(err.toString(), isEmpty);
    });
  });
}

/// Renders [register] into [output] and asserts what the rendered views must
/// hold whatever entries the register carries, and returns the views.
List<DecisionView> _expectAnchorsEveryBinding(String register, String output) {
  final views = renderRegister(
    registerDirectory: register,
    templateFile: _templateFile,
    outputDirectory: output,
  );
  final graph = DecisionGraph(readRegister(register));
  final binding = graph.entries.values
      .where((entry) => graph.isBinding(entry.slug))
      .toList();
  String anchor(String slug) => '<a id="$slug"></a>';
  int viewAnchoring(String slug) =>
      views.indexWhere((view) => view.content.contains(anchor(slug)));

  expect(views, isNotEmpty);
  expect(binding, isNotEmpty);

  // Views are numbered from one, zero-padded, with no gaps, and each is
  // named for an entry it anchors.
  for (var i = 0; i < views.length; i++) {
    final name = views[i].fileName;
    final prefix = '${(i + 1).toString().padLeft(4, '0')}-';
    expect(name, startsWith(prefix));
    expect(name, endsWith('.md'));
    final slug = name.substring(prefix.length, name.length - '.md'.length);
    expect(graph.entries.keys, contains(slug), reason: name);
    expect(views[i].content, contains(anchor(slug)), reason: name);
  }

  for (final entry in binding) {
    expect(
      views.where((view) => view.content.contains(anchor(entry.slug))).length,
      1,
      reason: entry.slug,
    );
  }

  // The format's root is the register's earliest entry, so it leads.
  expect(views.first.fileName, '0001-the-decision-register.md');

  // The CLI's distribution is a lineage apart from the format's, and the
  // Gas City pack's lineage joins it because the vended register CI gate
  // amends both.
  const distribution = 'the-decisions-cli-ships-as-prebuilt-binaries';
  const lintGate = 'decisions-lint-gate-is-the-vended-register-ci-check';
  const noOrders =
      'the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-'
      'each-rigs-ci';
  const guideStubs = 'the-register-ships-to-gas-city-as-a-pack-of-guide-stubs';
  final distributionView = viewAnchoring(distribution);
  expect(distributionView, isNonNegative);
  expect(distributionView, isNot(viewAnchoring('the-decision-register')));
  for (final slug in [lintGate, noOrders, guideStubs]) {
    expect(viewAnchoring(slug), distributionView, reason: slug);
  }
  expect(
    graph
        .outgoingFrom(lintGate, kind: DecisionEdgeKind.updates)
        .map((edge) => edge.target.slug),
    containsAll([distribution, noOrders]),
  );

  return views;
}

const _temporarySlug = 'a-temporary-entry-with-no-bead-and-no-edge';

/// Writes an accepted entry with no bead and no edge into [register].
void _writeTemporaryEntry(String register) {
  File(p.join(register, '2026-11-09-$_temporarySlug.md')).writeAsStringSync('''
---
status: accepted
date: 2026-11-09
decision-makers: ["nico"]
consulted: []
informed: []
register:
  spec: 1
  slug: "$_temporarySlug"
  surfaces:
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $_temporarySlug

## Decision Outcome

Fixture.
''');
}

Future<int> _run(List<String> args, StringBuffer out, StringBuffer err) =>
    DecisionsCommandRunner(output: out, error: err).run(args);

Map<String, List<int>> _markdownBytes(Directory directory) {
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.md')
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  return {
    for (final file in files) p.basename(file.path): file.readAsBytesSync(),
  };
}
