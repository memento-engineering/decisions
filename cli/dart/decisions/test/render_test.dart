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
    // tooling, then the doctor verb, which governs tooling, then the
    // retirement of migrate-legacy, which governs tooling and amends no
    // entry, then the stream contract every verb shares, which governs
    // tooling and amends no entry, then the tier table, which defers the verb
    // list without amending an entry, then the starter style guide, which
    // adds a template without amending an entry, then the resurface verb,
    // which states a new writer of surfaces without amending an entry, then
    // the nightly run against gc latest, which governs CI and amends no
    // entry, then the index's refusal of an unread register, which governs
    // tooling and amends no entry. The
    // Gas City pack's lineage joins the CLI's distribution: the vended
    // register CI gate amends both.
    expect(views.map((view) => view.fileName), [
      '0001-the-decision-register.md',
      '0002-the-decisions-cli-ships-as-prebuilt-binaries.md',
      '0003-a-registers-style-md-is-its-style-guide-and-uppercase-files-are-'
          'not-entries.md',
      '0004-the-decisions-binary-carries-its-own-agent-instructions.md',
      '0005-decisions-doctor-answers-whether-this-binary-can-work-this-'
          'register.md',
      '0006-decisions-migrate-legacy-is-retired-with-the-legacy-registers-it-'
          'converted.md',
      '0007-every-verb-prints-refusals-and-errors-on-stderr-and-results-on-'
          'stdout.md',
      '0008-spec-tier-table-describes-capabilities-and-defers-the-verb-list-'
          'to-the-cli.md',
      '0009-templates-style-md-is-the-starter-style-guide-for-a-register.md',
      '0010-decisions-resurface-re-points-a-surface-after-a-move-and-records-'
          'no-entry.md',
      '0011-a-nightly-run-checks-the-gas-city-pack-against-gc-latest.md',
      '0012-index-surface-refuses-a-register-the-index-does-not-carry.md',
    ]);
    final combined = views.map((view) => view.content).join('\n');
    final graph = DecisionGraph(readRegister(_selfHostedRegister));
    final binding = graph.entries.values
        .where((entry) => graph.isBinding(entry.slug))
        .toList();

    expect(binding, hasLength(28));
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

    expect(views, hasLength(12));
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
