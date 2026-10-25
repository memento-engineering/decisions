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
    final output = p.join(sandbox.path, 'views');
    final views = renderRegister(
      registerDirectory: _selfHostedRegister,
      templateFile: _templateFile,
      outputDirectory: output,
    );

    // The format's lineage, which the write verb amends as a tier-1 verb,
    // then the CLI's distribution, which governs tooling and amends no format
    // decision, then register documents, which add to the format without
    // amending an entry, then the binary's agent instructions, which govern
    // tooling.
    expect(views.map((view) => view.fileName), [
      '0001-the-decision-register.md',
      '0002-the-decisions-cli-ships-as-prebuilt-binaries.md',
      '0003-a-registers-style-md-is-its-style-guide-and-uppercase-files-are-'
          'not-entries.md',
      '0004-the-decisions-binary-carries-its-own-agent-instructions.md',
    ]);
    final combined = views.map((view) => view.content).join('\n');
    final graph = DecisionGraph(readRegister(_selfHostedRegister));
    final binding = graph.entries.values
        .where((entry) => graph.isBinding(entry.slug))
        .toList();

    expect(binding, hasLength(13));
    for (final entry in binding) {
      expect(combined, contains('<a id="${entry.slug}"></a>'));
    }
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

    expect(views, hasLength(4));
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
}

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
