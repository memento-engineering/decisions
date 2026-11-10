import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'entry.dart';
import 'register_union.dart';
import 'render.dart';
import 'slug_limit_option.dart';

/// `decisions render`: regenerates one register's lineage views.
final class RenderCommand extends Command<int> {
  /// Creates the verb, writing results to [output] and refusals to [error].
  ///
  /// The register is read under its limit in [slugLimits] unless
  /// `--max-slug-length` names one for the run.
  RenderCommand({
    StringSink? output,
    StringSink? error,
    DecisionSlugLimits slugLimits = const DecisionSlugLimits(),
  }) : _output = output ?? stdout,
       _error = error ?? stderr,
       _slugLimits = slugLimits {
    argParser
      ..addOption(
        'template',
        valueHelp: 'file',
        help: 'The view template every view is rendered through.',
      )
      ..addOption(
        'output',
        valueHelp: 'dir',
        help:
            'The directory whose .md views are replaced '
            '(default <register>/views).',
      );
    addMaxSlugLengthOption(argParser);
  }

  final StringSink _output;
  final StringSink _error;
  final DecisionSlugLimits _slugLimits;

  @override
  String get name => 'render';

  @override
  String get description =>
      'Regenerate one register\'s lineage views from its graph.\n'
      '\n'
      'Exits 0 when every view is written, printing each written path on '
      'stdout.\nExits 1 with "error: <reason>" on stderr when the register or '
      'template cannot\nbe read or the template is invalid, and nothing in the '
      'output directory changes.\nA missing --template or a wrong number of '
      'register paths is a usage error (64).';

  @override
  void printUsage() => _output.writeln(usage);

  @override
  int run() {
    final results = argResults!;
    if (results.rest.length != 1) {
      usageException('Expected exactly one register path.');
    }
    final template = results.option('template');
    if (template == null || template.isEmpty) {
      usageException('render needs --template <file>');
    }
    final slugLimits = resolveSlugLimits(this, _slugLimits);
    final register = results.rest.single;
    final requested = results.option('output');
    final outputDirectory = requested == null || requested.isEmpty
        ? p.join(register, 'views')
        : requested;

    try {
      final views = renderRegister(
        registerDirectory: register,
        templateFile: template,
        outputDirectory: outputDirectory,
        slugLimits: slugLimits,
      );
      for (final view in views) {
        _output.writeln(p.join(outputDirectory, view.fileName));
      }
      return 0;
    } on DecisionRenderException catch (error) {
      _error.writeln('error: ${error.message}');
    } on DecisionParseException catch (error) {
      _error.writeln('error: ${error.file}: ${error.message}');
    } on FileSystemException catch (error) {
      final reason = error.osError?.message ?? error.message;
      final path = error.path;
      _error.writeln(path == null ? 'error: $reason' : 'error: $path: $reason');
    }
    return 1;
  }
}
