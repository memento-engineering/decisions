import 'dart:io';

import 'package:path/path.dart' as p;

import 'entry.dart';
import 'graph.dart';

const _entryOpen = '{{#entries}}';
const _entryClose = '{{/entries}}';

/// One generated decision view ready to be written.
final class DecisionView {
  /// Creates a generated view named [fileName] with byte content [content].
  const DecisionView({required this.fileName, required this.content});

  /// The zero-padded basename under `docs/decisions/views/`.
  final String fileName;

  /// The complete deterministic Markdown, including its final newline.
  final String content;
}

/// Thrown when the configured view layout cannot be rendered.
final class DecisionRenderException implements Exception {
  /// Creates a render failure with [message].
  const DecisionRenderException(this.message);

  /// What made the layout invalid.
  final String message;

  @override
  String toString() => 'DecisionRenderException: $message';
}

/// Renders deterministic lineage views without performing file-system writes.
List<DecisionView> renderViews({
  required DecisionGraph graph,
  required String template,
}) {
  _validateTemplate(template);
  final components = _connectedComponents(graph);
  final views = <DecisionView>[];

  for (var index = 0; index < components.length; index++) {
    final entries = components[index];
    final number = (index + 1).toString().padLeft(4, '0');
    final name = entries.first.slug;
    views.add(
      DecisionView(
        fileName: '$number-$name.md',
        content: _renderView(
          graph: graph,
          template: template,
          entries: entries,
          number: number,
          name: name,
        ),
      ),
    );
  }

  return List<DecisionView>.unmodifiable(views);
}

/// Reads a register and template, then replaces its generated Markdown views.
List<DecisionView> renderRegister({
  required String registerDirectory,
  required String templateFile,
  required String outputDirectory,
}) {
  final graph = DecisionGraph(readRegister(registerDirectory));
  final template = File(templateFile).readAsStringSync();
  final views = renderViews(graph: graph, template: template);
  final output = Directory(outputDirectory);

  output.createSync(recursive: true);
  final generatedFiles =
      output
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path) == '.md')
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  for (final file in generatedFiles) {
    file.deleteSync();
  }
  for (final view in views) {
    File(p.join(output.path, view.fileName)).writeAsStringSync(view.content);
  }

  return views;
}

List<List<DecisionEntry>> _connectedComponents(DecisionGraph graph) {
  final orderedEntries = graph.entries.values.toList()..sort(_compareEntries);
  final adjacency = {
    for (final entry in orderedEntries) entry.slug: <String>{},
  };

  for (final edge in graph.edges) {
    adjacency[edge.source.slug]!.add(edge.target.slug);
    adjacency[edge.target.slug]!.add(edge.source.slug);
  }

  final visited = <String>{};
  final components = <List<DecisionEntry>>[];

  for (final seed in orderedEntries) {
    if (!visited.add(seed.slug)) continue;
    final frontier = <String>[seed.slug];
    final component = <DecisionEntry>[];

    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();
      component.add(graph.entries[current]!);
      final neighbours = adjacency[current]!.toList()..sort();

      for (final neighbour in neighbours) {
        if (visited.add(neighbour)) {
          frontier.add(neighbour);
        }
      }
    }

    component.sort(_compareEntries);
    components.add(List<DecisionEntry>.unmodifiable(component));
  }

  return List<List<DecisionEntry>>.unmodifiable(components);
}

int _compareEntries(DecisionEntry left, DecisionEntry right) {
  final byDate = left.date.compareTo(right.date);
  return byDate == 0 ? left.slug.compareTo(right.slug) : byDate;
}

String _renderView({
  required DecisionGraph graph,
  required String template,
  required List<DecisionEntry> entries,
  required String number,
  required String name,
}) {
  final open = template.indexOf(_entryOpen);
  final close = template.indexOf(_entryClose, open + _entryOpen.length);
  final entryTemplate = template.substring(open + _entryOpen.length, close);
  final outerValues = {'number': number, 'name': name};
  final prefix = _fill(template.substring(0, open), outerValues);
  final suffix = _fill(
    template.substring(close + _entryClose.length),
    outerValues,
  );
  final renderedEntries = entries.map((entry) {
    return _fill(entryTemplate, {
      ...outerValues,
      'slug': entry.slug,
      'date': entry.date,
      'force': _forceLabel(graph.forceOf(entry.slug)),
      'superseded_by': _successors(graph, entry),
      'body': entry.body,
    });
  }).join();

  return '${('$prefix$renderedEntries$suffix').trimRight()}\n';
}

String _forceLabel(DecisionForce force) => switch (force) {
  DecisionForce.binding => 'binding',
  DecisionForce.superseded => 'superseded',
  DecisionForce.vacated => 'vacated',
  DecisionForce.rejected => 'rejected',
};

String _successors(DecisionGraph graph, DecisionEntry entry) {
  final successors = graph.obsoletedBy(entry.slug).toList()
    ..sort(_compareEntries);
  if (successors.isEmpty) return '—';
  return successors
      .map((successor) => '[`${successor.slug}`](#${successor.slug})')
      .join(', ');
}

String _fill(String source, Map<String, String> values) {
  var result = source;
  for (final MapEntry(:key, :value) in values.entries) {
    result = result.replaceAll('{{$key}}', value);
  }
  return result;
}

void _validateTemplate(String template) {
  if (template.split(_entryOpen).length != 2 ||
      template.split(_entryClose).length != 2) {
    throw const DecisionRenderException(
      'view template requires exactly one entries block',
    );
  }

  final open = template.indexOf(_entryOpen);
  final close = template.indexOf(_entryClose, open + _entryOpen.length);
  if (close < open) {
    throw const DecisionRenderException(
      'view template closes entries before opening it',
    );
  }

  final block = template.substring(open + _entryOpen.length, close);
  final outside =
      template.substring(0, open) +
      template.substring(close + _entryClose.length);
  for (final token in ['number', 'name']) {
    if (!outside.contains('{{$token}}')) {
      throw DecisionRenderException('view template is missing {{$token}}');
    }
  }
  for (final token in ['slug', 'date', 'force', 'superseded_by', 'body']) {
    if (!block.contains('{{$token}}')) {
      throw DecisionRenderException('entries block is missing {{$token}}');
    }
  }

  const allowed = {
    _entryOpen,
    _entryClose,
    '{{number}}',
    '{{name}}',
    '{{slug}}',
    '{{date}}',
    '{{force}}',
    '{{superseded_by}}',
    '{{body}}',
  };
  final tokens = RegExp(
    r'{{(?:#|/)?[a-z_]+}}',
  ).allMatches(template).map((match) => match.group(0)!);
  final unknown = tokens.where((token) => !allowed.contains(token)).toSet();
  if (unknown.isNotEmpty) {
    final sorted = unknown.toList()..sort();
    throw DecisionRenderException(
      'view template has unsupported tokens: ${sorted.join(', ')}',
    );
  }
}
