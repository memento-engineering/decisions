import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'guide.dart';

/// The register directory a verb reads when `--register` is not given.
const _defaultRegister = 'docs/decisions';

/// The register's own style guide, by filename inside the register.
const _styleGuide = 'STYLE.md';

/// The marker line that identifies a file written by `skills install`.
///
/// A file carrying it is a stub the next install may overwrite; any other
/// file at a stub's path is the adopter's, and install refuses to touch it.
const skillStubMarker =
    '<!-- decisions skills install: stub; reinstalling overwrites this file -->';

/// Renders the `SKILL.md` stub for [guide]: the canonical front matter, and a
/// body that defers to `<command> guide <name>`.
String skillStub(Guide guide, {String command = 'decisions'}) =>
    '''
---
name: ${guide.name}
description: ${jsonEncode(guide.description)}
---

$skillStubMarker

Run `$command guide ${guide.name}` and follow the instructions it prints.
They ship inside the installed `decisions` binary, so they always match the
engine that will lint your work, and they carry this register's STYLE.md
when it has one.
''';

/// `decisions prime`: a short orientation for an agent arriving in a repo.
///
/// It names the register and its style guide, lists the sibling verbs with
/// when to reach for each, and points at `guide` and `--help` rather than
/// restating any verb's contract.
final class PrimeCommand extends Command<int> {
  /// Creates the verb, writing its orientation to [output].
  PrimeCommand({required StringSink output}) : _output = output {
    argParser.addOption(
      'register',
      defaultsTo: _defaultRegister,
      help: 'Decision register to orient on.',
    );
  }

  final StringSink _output;

  @override
  String get name => 'prime';

  @override
  String get description => 'Orient an agent: the register, verbs, guides.';

  @override
  int run() {
    if (argResults!.rest.isNotEmpty) {
      usageException('prime takes no positional arguments.');
    }
    final command = _invocation(this);
    final register = argResults!.option('register')!;
    final style = p.join(register, _styleGuide);
    final verbs = [
      for (final MapEntry(key: name, value: verb)
          in (parent?.subcommands ?? runner!.commands).entries)
        if (name == verb.name && !verb.hidden && name != 'help') verb,
    ];
    final width = verbs.fold(
      0,
      (w, verb) => verb.name.length > w ? verb.name.length : w,
    );

    _output
      ..writeln('$command: the decision register.')
      ..writeln()
      ..writeln('One markdown file per decision, together a citation graph')
      ..writeln('with force. A decision binds the moment its entry is written;')
      ..writeln('only a docket changes its force (obsolete, update, vacate).')
      ..writeln();
    if (!Directory(register).existsSync()) {
      _output.writeln(
        'Register: $register not found. Run from the repository root, '
        'or pass --register.',
      );
    } else {
      _output
        ..writeln('Register: $register')
        ..writeln(
          File(style).existsSync()
              ? 'Style guide: $style. Read it before writing an entry body.'
              : 'Style guide: none (no $style).',
        );
    }
    _output
      ..writeln()
      ..writeln('Verbs, and when to reach for each:');
    for (final verb in verbs) {
      _output.writeln(
        '  ${verb.name.padRight(width)}  '
        '${_whenToReach(verb.name) ?? verb.description}',
      );
    }
    _output
      ..writeln()
      ..writeln('Judgement lives in the guides: `$command guide` lists them,')
      ..writeln('`$command guide <topic>` prints one.')
      ..writeln('Each verb\'s contract: `$command <verb> --help`.');
    return 0;
  }
}

/// `decisions guide [topic]`: the bundled skills, printed for an agent.
///
/// With no topic it lists the topics; with one it prints that guide's body,
/// then the register's `STYLE.md` under a heading naming the file.
final class GuideCommand extends Command<int> {
  /// Creates the verb over [guides], writing to [output].
  GuideCommand({required StringSink output, List<Guide> guides = bundledGuides})
    : _output = output,
      _guides = guides {
    argParser.addOption(
      'register',
      defaultsTo: _defaultRegister,
      help: 'Decision register whose STYLE.md is appended to a guide.',
    );
  }

  final StringSink _output;
  final List<Guide> _guides;

  @override
  String get name => 'guide';

  @override
  String get description => 'Print a guide: how to decide, how to ratify.';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length > 1) usageException('Expected at most one topic.');
    if (rest.isEmpty) {
      _output.writeln('Guides (`${_invocation(this)} guide <topic>`):');
      for (final guide in _guides) {
        _output.writeln('  ${guide.name}: ${guide.description}');
      }
      return 0;
    }
    final topic = rest.single;
    final guide = _guides.where((guide) => guide.name == topic).firstOrNull;
    if (guide == null) {
      usageException(
        'No guide "$topic". Topics: '
        '${_guides.map((guide) => guide.name).join(', ')}.',
      );
    }
    _output.write(guide.body);
    final style = File(p.join(argResults!.option('register')!, _styleGuide));
    if (style.existsSync()) {
      final content = style.readAsStringSync();
      _output
        ..writeln()
        ..writeln('# Register style guide: ${style.path}')
        ..writeln()
        ..write(content.endsWith('\n') ? content : '$content\n');
    }
    return 0;
  }
}

/// `decisions skills`: manage skill stubs that defer to `guide`.
final class SkillsCommand extends Command<int> {
  /// Creates the group over [guides], writing to [output] and [error].
  SkillsCommand({
    required StringSink output,
    required StringSink error,
    List<Guide> guides = bundledGuides,
  }) {
    addSubcommand(
      _SkillsInstallCommand(output: output, error: error, guides: guides),
    );
  }

  @override
  String get name => 'skills';

  @override
  String get description => 'Install skill stubs that defer to `guide`.';
}

final class _SkillsInstallCommand extends Command<int> {
  _SkillsInstallCommand({
    required StringSink output,
    required StringSink error,
    required List<Guide> guides,
  }) : _output = output,
       _error = error,
       _guides = guides;

  final StringSink _output;
  final StringSink _error;
  final List<Guide> _guides;

  @override
  String get name => 'install';

  @override
  String get description =>
      'Write <dir>/<name>/SKILL.md stubs; overwrite only earlier stubs.';

  @override
  int run() {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Expected exactly one <dir>.');
    final command = _invocation(parent!);
    final targets = {
      for (final guide in _guides)
        p.join(rest.single, guide.name, 'SKILL.md'): skillStub(
          guide,
          command: command,
        ),
    };
    final refused = [
      for (final path in targets.keys)
        if (_isForeign(path)) path,
    ];
    if (refused.isNotEmpty) {
      for (final path in refused) {
        _error.writeln(
          'error: $path exists and is not a decisions stub; '
          'move it aside or install into another directory',
        );
      }
      return 1;
    }
    for (final MapEntry(key: path, value: stub) in targets.entries) {
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(stub);
      _output.writeln('wrote $path');
    }
    return 0;
  }

  /// Whether [path] holds something install must not overwrite.
  static bool _isForeign(String path) =>
      switch (FileSystemEntity.typeSync(path, followLinks: false)) {
        FileSystemEntityType.notFound => false,
        FileSystemEntityType.file => !File(
          path,
        ).readAsStringSync().contains(skillStubMarker),
        _ => true,
      };
}

/// How [command]'s parent chain is invoked, e.g. `decisions` standalone or
/// `station decisions` under a station.
String _invocation(Command<int> command) {
  final names = <String>[];
  for (Command<int>? node = command.parent; node != null; node = node.parent) {
    names.insert(0, node.name);
  }
  return [command.runner!.executableName, ...names].join(' ');
}

/// The one-line cue prime prints for a verb it knows; `null` falls back to the
/// verb's own description.
String? _whenToReach(String verb) => switch (verb) {
  'search' => 'look for precedent before deciding anything',
  'index' =>
    'list the decisions governing a path (--surface) before changing it',
  'new' => 'record a decision just made; `guide decide` says how',
  'lint' => 'validate the register after any write',
  'obsolete' ||
  'update' ||
  'vacate' => 'only to carry out a docket ruling; `guide ratify` says how',
  'migrate-legacy' => 'once, to convert an ADR-0000 register',
  'prime' => 'this orientation',
  'guide' => 'the judgement half: how to decide, how to hold a docket',
  'skills' => 'install skill stubs that defer to `guide`',
  _ => null,
};
