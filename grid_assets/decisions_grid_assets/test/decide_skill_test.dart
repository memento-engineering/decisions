import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

final Directory _packageRoot = Directory.current;
final Directory _repoRoot = Directory(
  p.normalize(p.join(_packageRoot.path, '..', '..')),
);
final File _canonicalSkill = File(
  p.join(_repoRoot.path, 'skills', 'decide', 'SKILL.md'),
);

final RegExpMatch _parts = RegExp(
  r'^---\n(.*?)\n---\n\n?(.*)$',
  dotAll: true,
).firstMatch(_canonicalSkill.readAsStringSync())!;

String get _description =>
    (loadYaml(_parts.group(1)!) as YamlMap)['description'] as String;

String get _body => _parts.group(2)!;

/// [_body] with every run of whitespace folded to one space, so a cue does
/// not depend on where the prose wraps.
String get _prose => _body.replaceAll(RegExp(r'\s+'), ' ');

/// The one fenced `sh` block that shows the `decisions new` call.
String get _writeCall => RegExp(
  r'```sh\n(decisions new .*?)```',
  dotAll: true,
).firstMatch(_body)!.group(1)!;

/// The flags `decisions new` actually accepts.
final Set<String> _newFlags = {
  for (final name in DecisionNewCommand().argParser.options.keys) '--$name',
};

void main() {
  test('the description leads with when to use it, and when not', () {
    expect(
      _description,
      startsWith(
        'Use right after a placement, naming, seam, policy or human ruling '
        'has been decided, by an agent or a human,',
      ),
    );
    expect(_description, contains('decisions new'));
    expect(
      _description,
      endsWith(
        "Not for changing an existing decision's force; "
        'that is the ratify skill.',
      ),
    );
  });

  test('the body is judgement only, short enough to read whole', () {
    final lines = _body.split('\n').where((line) => line.trim().isNotEmpty);
    expect(lines.length, lessThanOrEqualTo(70));
    // The mechanics `decisions new` owns are no longer transcribed as shell.
    for (final mechanic in [
      'rg -n',
      'awk ',
      r'^[a-z0-9]+(-[a-z0-9]+)*$',
      'legacy-id:',
      'spec: 1',
    ]) {
      expect(_body, isNot(contains(mechanic)), reason: mechanic);
    }
  });

  test('defers the write to decisions new, then its next: lines', () {
    expect(_prose, contains('`decisions new` owns the mechanics'));
    expect(_writeCall, startsWith('decisions new <slug> --title'));
    for (final flag in RegExp(r'--[a-z-]+').allMatches(_writeCall)) {
      expect(_newFlags, contains(flag[0]), reason: 'unknown flag ${flag[0]}');
    }
    for (final flag in [
      '--decision-maker',
      '--consulted',
      '--informed',
      '--obsoletes',
      '--updates',
      '--bead',
      '--body -',
    ]) {
      expect(_prose, contains('`$flag'), reason: flag);
      expect(_newFlags, contains(flag.split(' ').first), reason: flag);
    }
    expect(
      _prose,
      contains('run every printed `next:` line exactly as printed'),
    );
    expect(_prose, contains('Never hand-write `status`'));
    expect(_prose, contains('run no other force verb unless'));
    expect(_prose, contains('decisions lint docs/decisions --repo-root .'));
  });

  test('keeps the judgement a program cannot check', () {
    for (final cue in [
      '## When an entry is warranted',
      '`decisions search <terms>`',
      '## Surfaces: the narrowest that govern',
      'git ls-files --others --exclude-standard',
      'never a catch-all',
      '## Authorship, honestly',
      'a human ruling names the human, an autonomous call the agent seat, '
          'a joint call both',
      '## Edges',
      'The new entry replaces the named decision entirely.',
      'The new entry amends the named decision, which stays in force.',
      'Do not add an edge to make the graph look complete.',
      'The title is declarative',
      '`## Considered Options` only when options were genuinely weighed',
      'omit a section rather than invent content for it',
    ]) {
      expect(_prose, contains(cue), reason: cue);
    }
  });

  test("honours the register's STYLE.md", () {
    expect(_prose, contains('When the register has a `STYLE.md`, follow it'));
    expect(_prose, contains('`decisions guide decide` prints it'));
  });

  test('mints a decision bead only where beads resolves', () {
    expect(_prose, contains('`command -v bd && bd where --json` succeeds'));
    expect(_prose, contains('--type decision'));
    expect(_prose, contains('Otherwise omit `--bead`'));
    expect(_prose, contains('Never install beads or guess an id.'));
  });

  test('falls back to the template and spec without the binary', () {
    expect(_prose, contains('## Without the decisions binary'));
    expect(_prose, contains('brew install memento-engineering/tap/decisions'));
    expect(_prose, contains('pinned release download'));
    expect(_prose, contains('`templates/decision.md`'));
    expect(_prose, contains('`SPEC.md`'));
    expect(_prose, contains('never `proposed`'));
  });

  test(
    'the prescribed sections pass decisions new, and an edge prints next:',
    () {
      final temp = Directory.systemTemp.createTempSync('decide-skill-');
      addTearDown(() => temp.deleteSync(recursive: true));
      File(p.join(temp.path, 'lib', 'src', 'router.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('final class Router {}\n');
      final register = p.join(temp.path, 'docs', 'decisions');
      const body =
          '## Context and Problem Statement\n'
          '\n'
          'One routing owner was required.\n'
          '\n'
          '## Decision Outcome\n'
          '\n'
          'The package seam owns routing.\n'
          '\n'
          '### Consequences\n'
          '\n'
          '* Good, because ownership is explicit.\n'
          '* Bad, because callers depend on the seam.\n';
      final recorder = DecisionRecordService();
      DecisionRecordResult record(
        String slug, {
        List<String> updates = const [],
      }) => recorder.record(
        registerPath: register,
        repoRoot: temp.path,
        draft: DecisionDraft(
          slug: slug,
          title: 'The package seam owns routing',
          surfaces: const ['lib/src/router.dart'],
          decisionMakers: const ['agent'],
          updates: updates,
          date: '2026-10-25',
          body: body,
        ),
      );

      expect(record('place-router-seam').nextSteps, isEmpty);
      final amended = record(
        'the-router-seam-also-owns-deep-links',
        updates: ['place-router-seam'],
      );

      expect(
        amended.nextSteps.single.command,
        startsWith(
          'decisions update place-router-seam '
          '--by the-router-seam-also-owns-deep-links',
        ),
      );
    },
  );
}
