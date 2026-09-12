import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'index_command.dart';
import 'search.dart';

/// Vends citation-ready lexical precedent search over decision registers.
final class DecisionSearchCommand extends Command<int> {
  /// Creates the command with lazy register resolution and injectable sinks.
  DecisionSearchCommand({
    RegisterPathResolver? registerPaths,
    StringSink? output,
    StringSink? error,
    DecisionSearchService service = const DecisionSearchService(),
  }) : _registerPaths = registerPaths ?? _defaultRegisterPaths,
       _output = output ?? stdout,
       _error = error ?? stderr,
       _service = service {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Emit one schema-1 JSON search-hit object per line.',
      )
      ..addMultiOption(
        'status',
        valueHelp: 'state',
        allowed: const <String>['accepted', 'obsoleted', 'vacated', 'rejected'],
        help: 'Filter by force-state alias; repeat for alternatives.',
      )
      ..addMultiOption(
        'decision-maker',
        valueHelp: 'name',
        help:
            'Filter by an exact decision-maker name; repeat for alternatives.',
      )
      ..addMultiOption(
        'slug',
        valueHelp: 'slug',
        help: 'Filter by an exact decision slug; repeat for alternatives.',
      )
      ..addMultiOption(
        'surface',
        valueHelp: 'register/path',
        help: 'Filter by a governed roster-qualified path.',
      )
      ..addMultiOption(
        'obsoletes',
        valueHelp: 'reference',
        help: 'Filter by an exact authored obsoletes reference.',
      )
      ..addMultiOption(
        'updates',
        valueHelp: 'reference',
        help: 'Filter by an exact authored updates reference.',
      )
      ..addMultiOption(
        'obsoleted-by',
        valueHelp: 'reference',
        help: 'Filter by an exact cached obsoleted-by reference.',
      )
      ..addMultiOption(
        'updated-by',
        valueHelp: 'reference',
        help: 'Filter by an exact cached updated-by reference.',
      )
      ..addOption(
        'date-from',
        valueHelp: 'YYYY-MM-DD',
        help: 'Keep decisions on or after this date.',
      )
      ..addOption(
        'date-through',
        valueHelp: 'YYYY-MM-DD',
        help: 'Keep decisions on or before this date.',
      );
  }

  final RegisterPathResolver _registerPaths;
  final StringSink _output;
  final StringSink _error;
  final DecisionSearchService _service;

  @override
  String get name => 'search';

  @override
  String get description => 'Search decision registers for precedent.';

  @override
  FutureOr<int> run() {
    final results = argResults!;
    final query = results.rest.join(' ').trim();
    if (query.isEmpty) usageException('a search query is required');

    final dateFrom = _calendarDate('date-from');
    final dateThrough = _calendarDate('date-through');
    if (dateFrom != null &&
        dateThrough != null &&
        dateFrom.compareTo(dateThrough) > 0) {
      usageException('--date-from must not be after --date-through');
    }

    final registerPaths = _registerPaths().toList(growable: false);
    if (registerPaths.isEmpty) {
      usageException('at least one register directory is required');
    }

    final result = _service.search(
      query: query,
      registerPaths: registerPaths,
      filters: DecisionSearchFilters(
        statuses: results
            .multiOption('status')
            .map(_statusFilter)
            .toList(growable: false),
        dateFrom: dateFrom,
        dateThrough: dateThrough,
        decisionMakers: results.multiOption('decision-maker'),
        slugs: results.multiOption('slug'),
        surfaces: results.multiOption('surface'),
        obsoletes: results.multiOption('obsoletes'),
        updates: results.multiOption('updates'),
        obsoletedBy: results.multiOption('obsoleted-by'),
        updatedBy: results.multiOption('updated-by'),
      ),
    );
    for (final diagnostic in result.diagnostics) {
      _error.writeln(
        '${diagnostic.file}: [${diagnostic.ruleId}] ${diagnostic.message}',
      );
    }

    if (results.flag('json')) {
      for (final hit in result.hits) {
        _output.writeln(jsonEncode(hit.toJson()));
      }
    } else {
      for (final hit in result.hits) {
        _output.writeln(
          '${hit.register}#${hit.slug} [${hit.status}] ${hit.date} '
          '${hit.path} — ${hit.field}: ${hit.snippet}',
        );
      }
      _output.writeln(
        '${result.hits.length} hit(s) across ${registerPaths.length} '
        'register(s) for "$query"',
      );
    }
    return 0;
  }

  String? _calendarDate(String option) {
    final value = argResults!.option(option);
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    final parsed = DateTime.tryParse(value);
    if (match == null ||
        parsed == null ||
        parsed.year != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!) ||
        parsed.day != int.parse(match.group(3)!)) {
      usageException('--$option must be a calendar date in YYYY-MM-DD form');
    }
    return value;
  }

  static DecisionSearchStatusFilter _statusFilter(String value) =>
      switch (value) {
        'accepted' => DecisionSearchStatusFilter.accepted,
        'obsoleted' => DecisionSearchStatusFilter.obsoleted,
        'vacated' => DecisionSearchStatusFilter.vacated,
        'rejected' => DecisionSearchStatusFilter.rejected,
        _ => throw StateError('arg parser admitted unsupported status $value'),
      };

  static Iterable<String> _defaultRegisterPaths() => const <String>[
    'docs/decisions',
  ];
}
