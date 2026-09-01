import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Directory _packageRoot = Directory.current;
final Directory _repoRoot = Directory(
  p.normalize(p.join(_packageRoot.path, '..', '..')),
);
final File _canonicalSkill = File(
  p.join(_repoRoot.path, 'skills', 'decide', 'SKILL.md'),
);

String get _skill => _canonicalSkill.readAsStringSync();

void _expectInOrder(List<String> markers) {
  var cursor = 0;
  for (final marker in markers) {
    final index = _skill.indexOf(marker, cursor);
    expect(index, isNot(-1), reason: 'missing or out of order: $marker');
    cursor = index + marker.length;
  }
}

void main() {
  test('defines the lint-clean bare-minimal write contract', () {
    for (final field in [
      'status: accepted',
      'decision-makers:',
      'consulted: []',
      'informed: []',
      'spec: 1',
      'slug:',
      'surfaces:',
      'obsoletes: []',
      'updates: []',
      'obsoleted-by: null',
      'updated-by: []',
      'bead:',
      'legacy-id: null',
      '## Context and Problem Statement',
      '## Decision Outcome',
      '### Consequences',
      'decisions lint docs/decisions --repo-root .',
    ]) {
      expect(_skill, contains(field), reason: field);
    }

    final temp = Directory.systemTemp.createTempSync('decide-skill-');
    addTearDown(() => temp.deleteSync(recursive: true));
    File(p.join(temp.path, 'lib', 'src', 'router.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Router {}\n');
    final register = Directory(p.join(temp.path, 'docs', 'decisions'))
      ..createSync(recursive: true);
    File(p.join(register.path, '2026-08-31-place-router-seam.md'))
        .writeAsStringSync(
          '---\n'
          'status: accepted\n'
          'date: 2026-08-31\n'
          'decision-makers: [agent]\n'
          'consulted: []\n'
          'informed: []\n'
          'register:\n'
          '  spec: 1\n'
          '  slug: place-router-seam\n'
          '  surfaces: ["lib/src/router.dart"]\n'
          '  obsoletes: []\n'
          '  updates: []\n'
          '  obsoleted-by: null\n'
          '  updated-by: []\n'
          '  bead: dec-fixture\n'
          '  legacy-id: null\n'
          '---\n'
          '\n'
          '# Place the router at the package seam\n'
          '\n'
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
          '* Bad, because callers depend on the seam.\n',
        );

    final result = const DecisionLintService().lint(
      registerPath: register.path,
      repoRoot: temp.path,
    );
    expect(result.diagnostics, isEmpty);
  });

  test('checks slug collision before writing the entry', () {
    expect(_skill, contains(r'^[a-z0-9]+(-[a-z0-9]+)*$'));
    expect(_skill, contains('at most 60 characters'));
    _expectInOrder([
      "decision_slug='chosen-kebab-slug'",
      'rg -n --max-depth 1',
      'If this reports a collision, stop before minting a bead or writing a file.',
      '### 4. Mint the tracker identity before citing it',
      '### 5. Write one entry',
    ]);
  });

  test('mints a decision bead before citing it', () {
    expect(_skill, contains('--type decision'));
    expect(_skill, contains('Never guess or preallocate an id.'));
    _expectInOrder([
      'command -v bd',
      'bd where --json',
      r'bd create "$decision_title" --type decision',
      r'bd show "$decision_bead" --json',
      '### 5. Write one entry',
    ]);
  });

  test('keeps trackerless registers conformant', () {
    expect(
      _skill,
      contains(
        "When either capability check fails, keep `decision_bead='null'`. "
        'Do not install, initialize, or assume Beads.',
      ),
    );
    expect(_skill, contains('The slug remains the complete conformant identity.'));
  });

  test('derives governed surfaces from touched paths', () {
    expect(
      _skill,
      contains(
        '{ git diff --name-only --relative HEAD; '
        'git ls-files --others --exclude-standard; } | sort -u',
      ),
    );
    expect(_skill, contains('Use an exact path when the ruling governs one file.'));
    expect(_skill, contains('Use the narrowest directory glob'));
    expect(_skill, contains('For a deleted path, name the surviving governed parent'));
    expect(_skill, contains('Every `register.surfaces` item must match'));
  });

  test('keeps authored edge meanings distinct', () {
    expect(
      _skill,
      contains('The new entry replaces the named decision entirely.'),
    );
    expect(
      _skill,
      contains(
        'The new entry substantively amends the named decision, '
        'which remains in force.',
      ),
    );
    expect(_skill, contains('The prior entry was merely cited'));
    expect(_skill, contains('never hand-write a cached back-edge'));
  });

  test('records decision makers and omits invented options', () {
    expect(
      _skill,
      contains(
        'A human ruling names the human, an autonomous call names '
        'the agent seat, and a joint call names both.',
      ),
    );
    expect(
      _skill,
      contains(
        'If no options were genuinely weighed, do not add a '
        '`## Considered Options` section.',
      ),
    );
    expect(_skill, contains('empty list rather than invented participants'));
  });
}
