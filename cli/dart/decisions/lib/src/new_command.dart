import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

import 'index_command.dart';
import 'lint.dart';
import 'record.dart';
import 'register_union.dart';

/// Reads the whole of standard input, for `--body -`.
typedef DecisionInputReader = String Function();

/// `decisions new <slug>`: writes one entry with birth values after the
/// mechanical checks [DecisionRecorder] owns.
///
/// Exit codes: 0 written, with the result on stdout; 1 refused, with nothing
/// written and the reason on stderr; a missing required flag or slug is a
/// usage error.
final class DecisionNewCommand extends Command<int> {
  /// Creates the command. Without a [recorder], each run builds a
  /// [DecisionRecordService] over [linter] and the resolved roster.
  DecisionNewCommand({
    DecisionRecorder? recorder,
    DecisionLinter? linter,
    RegisterPathResolver? registerPaths,
    DecisionInputReader? readInput,
    StringSink? output,
    StringSink? error,
  }) : _recorder = recorder,
       _linter = linter,
       _registerPaths =
           registerPaths ?? (() => const <String>['docs/decisions']),
       _readInput = readInput ?? _readStdin,
       _output = output ?? stdout,
       _error = error ?? stderr {
    argParser
      ..addOption('title', valueHelp: 'text', help: 'The H1. Required.')
      ..addOption(
        'body',
        valueHelp: 'path',
        help:
            'Markdown after the H1, or - for stdin. Required; needs '
            '"## Context and Problem Statement" and "## Decision Outcome".',
      )
      ..addMultiOption(
        'surface',
        valueHelp: 'glob',
        help: 'Governed path or glob; repeat, at least one.',
      )
      ..addMultiOption(
        'decision-maker',
        valueHelp: 'name',
        help: 'Who made the call; repeat, at least one.',
      )
      ..addMultiOption('consulted', valueHelp: 'name', help: 'Gave input.')
      ..addMultiOption('informed', valueHelp: 'name', help: 'Was notified.')
      ..addMultiOption(
        'obsoletes',
        valueHelp: 'slug',
        help: 'Replaced entirely; slug or <repo>#<slug>.',
      )
      ..addMultiOption(
        'updates',
        valueHelp: 'slug',
        help: 'Amended, stays in force; slug or <repo>#<slug>.',
      )
      ..addOption(
        'bead',
        valueHelp: 'id',
        help: 'Minted decision bead id; omit when trackerless.',
      )
      ..addOption(
        'date',
        valueHelp: 'YYYY-MM-DD',
        help: 'Entry date; defaults to today, local time.',
      )
      ..addOption(
        'register',
        defaultsTo: 'docs/decisions',
        help: 'Register to write into; created when absent.',
      )
      ..addOption(
        'repo-root',
        defaultsTo: '.',
        help: 'Repository root used to resolve surfaces.',
      )
      ..addMultiOption(
        'roster',
        valueHelp: 'register-path',
        help:
            'Sibling register for <repo>#<slug> edges; repeatable. Defaults '
            'to the composed register resolver.',
      );
  }

  final DecisionRecorder? _recorder;
  final DecisionLinter? _linter;
  final RegisterPathResolver _registerPaths;
  final DecisionInputReader _readInput;
  final StringSink _output;
  final StringSink _error;

  @override
  String get name => 'new';

  @override
  String get description =>
      'Record a decision: check identity and body, lint, write.\n'
      '\n'
      'Exits 0 when written, printing on stdout the path, the <repo>#<slug> '
      'handle and one "next:" line per --obsoletes or --updates edge: the '
      'force verb still to run so the target caches this entry. Exits 1 when '
      'refused, having written nothing, with the reason on stderr; a '
      'malformed invocation is a usage error.';

  @override
  String get invocation => super.invocation.replaceFirst(
    '[arguments]',
    '<slug> --title <text> --body <path> --surface <glob> '
        '--decision-maker <name> [options]',
  );

  @override
  void printUsage() => _output.writeln(usage);

  @override
  int run() {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Expected exactly one slug.');
    }
    final title = results.option('title');
    if (title == null || title.trim().isEmpty) {
      usageException('--title is required.');
    }
    final bodySource = results.option('body');
    if (bodySource == null || bodySource.isEmpty) {
      usageException('--body is required; pass a path, or - for stdin.');
    }
    final surfaces = results.multiOption('surface');
    if (surfaces.isEmpty) usageException('At least one --surface is required.');
    final decisionMakers = results.multiOption('decision-maker');
    if (decisionMakers.isEmpty) {
      usageException('At least one --decision-maker is required.');
    }

    final String body;
    try {
      body = bodySource == '-'
          ? _readInput()
          : File(bodySource).readAsStringSync();
    } on FileSystemException catch (error) {
      _error.writeln('error: cannot read body $bodySource: ${error.message}');
      return 1;
    } on FormatException catch (error) {
      _error.writeln('error: cannot read body $bodySource: ${error.message}');
      return 1;
    }

    final recorder =
        _recorder ??
        DecisionRecordService(linter: _linter, roster: _resolveRoster());
    try {
      final result = recorder.record(
        registerPath: results.option('register')!,
        repoRoot: results.option('repo-root')!,
        draft: DecisionDraft(
          slug: results.rest.single,
          title: title,
          surfaces: surfaces,
          decisionMakers: decisionMakers,
          consulted: results.multiOption('consulted'),
          informed: results.multiOption('informed'),
          obsoletes: results.multiOption('obsoletes'),
          updates: results.multiOption('updates'),
          bead: results.option('bead'),
          date: results.option('date'),
          body: body,
        ),
      );
      _output
        ..writeln('wrote ${result.path}')
        ..writeln(result.citation);
      for (final step in result.nextSteps) {
        _output.writeln('next: ${step.command}');
      }
      return 0;
    } on DecisionRecordException catch (error) {
      _error.writeln('error: ${error.message}');
      return 1;
    }
  }

  DecisionRoster _resolveRoster() {
    final explicit = argResults!.multiOption('roster');
    return DecisionRegisterRoster.fromRegisterPaths(
      explicit.isNotEmpty ? explicit : _registerPaths(),
    );
  }

  /// Reads standard input as UTF-8; invalid bytes throw a [FormatException],
  /// which [run] reports as a refusal.
  static String _readStdin() {
    // Latin-1 maps every byte to one code unit, so it carries the raw bytes
    // through line reading for a strict UTF-8 decode of the whole input.
    final bytes = BytesBuilder(copy: false);
    String? line;
    while ((line = stdin.readLineSync(
          encoding: latin1,
          retainNewlines: true,
        )) !=
        null) {
      bytes.add(latin1.encode(line!));
    }
    return utf8.decode(bytes.takeBytes());
  }
}
