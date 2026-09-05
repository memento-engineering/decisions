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
  p.join(_repoRoot.path, 'skills', 'ratify', 'SKILL.md'),
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

/// One sandbox repository: a register plus the surfaces its entries govern.
final class _Docket {
  _Docket()
    : root = Directory(
        p.join(
          Directory.systemTemp.createTempSync('ratify-skill-').path,
          'sandbox_repo',
        ),
      ) {
    register = Directory(p.join(root.path, 'docs', 'decisions'))
      ..createSync(recursive: true);
    File(p.join(root.path, 'lib', 'watcher.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('final class Watcher {}\n');
  }

  final Directory root;
  late final Directory register;

  File entry(
    String slug, {
    required int day,
    List<String> obsoletes = const [],
    List<String> decisionMakers = const ['agent'],
    List<String> surfaces = const ['lib/**'],
  }) {
    final date = '2026-01-${day.toString().padLeft(2, '0')}';
    final quotedSurfaces = surfaces.map((surface) => '"$surface"').join(', ');
    final file = File(p.join(register.path, '$date-$slug.md'));
    file.writeAsStringSync('''
---
status: accepted
date: $date
decision-makers: [${decisionMakers.join(', ')}]
consulted: []
informed: []
register:
  spec: 1
  slug: $slug
  surfaces: [$quotedSurfaces]
  obsoletes: [${obsoletes.join(', ')}]
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# $slug

## Decision Outcome

A fixture decision governing the sandbox surfaces.
''');
    return file;
  }

  DecisionLintResult get lint => const DecisionLintService().lint(
    registerPath: register.path,
    repoRoot: root.path,
  );

  void dispose() {
    final temp = root.parent;
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  }
}

void main() {
  test('binds the worksheet to the four ratified docket signals', () {
    for (final clause in [
      'decisions#docket-triggers',
      '| 1 | contradiction |',
      '| 2 | pending force request |',
      '| 3 | citation pressure |',
      '| 4 | growth |',
      '| 1, immediately |',
      '| 5 | the citation ledger |',
      '| 10 | `docket_new` |',
      'It does NOT fire on the calendar, on bead\ncloses, on landings',
      'Hold a docket for ONE register',
      'Never report an unmeasured signal as zero.',
    ]) {
      expect(_skill, contains(clause), reason: clause);
    }
  });

  test('reads the two commands and parses their JSON, never their prose', () {
    _expectInOrder([
      r'decisions lint "$docket_register" --repo-root . --json',
      r'decisions index > "$docket_scratch/index.json"',
      'Never scrape the prose form of either command.',
      'Only decisions whose `originRegister` is the register under docket may '
          'be RULED',
    ]);
    expect(
      _skill,
      contains('with NO positional register argument is load-bearing'),
    );
  });

  test('uses the docket entry as the only per-register marker', () {
    expect(_skill, contains('slug: docket-{YYYY-MM-DD}'));
    expect(
      _skill,
      contains(
        r"'^[[:space:]]*slug:[[:space:]]*docket-[0-9]{4}-[0-9]{2}-[0-9]{2}"
        r"[[:space:]]*$'",
      ),
    );
    expect(_skill, contains('No other state exists, and none may'));
    expect(_skill, contains('Hold at most one docket per register per day.'));
    _expectInOrder([
      '### 5. Apply the accepted rows in this order',
      "### 6. Record the docket's own entry, last, and validate",
      'write it even when every row was rejected',
      'decisions lint docs/decisions --repo-root .',
    ]);
  });

  test('a stale force cache and a contradiction produce distinct rows', () {
    final docket = _Docket();
    addTearDown(docket.dispose);
    docket.entry('poll-only', day: 1);
    docket.entry('watch-allowed', day: 2);
    docket.entry('stale-target', day: 3);
    docket.entry('force-request', day: 4, obsoletes: const ['stale-target']);

    final result = docket.lint;
    expect(result.isClean, isFalse);
    expect(
      result.diagnostics
          .where((d) => d.file.endsWith('2026-01-03-stale-target.md'))
          .map((d) => d.ruleId)
          .toSet(),
      {DecisionLintRules.forceObsoletedBy, DecisionLintRules.forceStatus},
    );

    expect(
      DecisionIndex.fromRegisterPaths([docket.register.path])
          .governing('sandbox_repo/lib/watcher.dart')
          .decisions
          .map((decision) => decision.slug)
          .toSet(),
      containsAll(['poll-only', 'watch-allowed']),
    );

    expect(
      _skill,
      contains(
        '| pending force request | 2 | the force operation the request '
        'already authored |',
      ),
    );
    expect(
      _skill,
      contains(
        '| contradiction | 1 | a new disposition entry authoring the '
        'resolving edge, then its force operation |',
      ),
    );
  });

  test('accepting each row emits its force operation and lints clean', () {
    final docket = _Docket();
    addTearDown(docket.dispose);
    final pollOnly = docket.entry('poll-only', day: 1);
    final watchAllowed = docket.entry('watch-allowed', day: 2);
    final staleTarget = docket.entry('stale-target', day: 3);
    docket.entry('force-request', day: 4, obsoletes: const ['stale-target']);
    const service = DecisionMutationService();

    service.obsolete(
      registerPath: docket.register.path,
      repoRoot: docket.root.path,
      target: 'stale-target',
      successor: 'force-request',
    );
    expect(parseEntry(staleTarget.path).status, 'superseded by force-request');
    expect(parseEntry(staleTarget.path).cachedObsoletedBy, 'force-request');

    docket.entry(
      'poll-only-governs-watching',
      day: 5,
      obsoletes: const ['watch-allowed'],
      decisionMakers: const ['nico', 'ratify'],
    );
    service.obsolete(
      registerPath: docket.register.path,
      repoRoot: docket.root.path,
      target: 'watch-allowed',
      successor: 'poll-only-governs-watching',
    );
    expect(
      parseEntry(watchAllowed.path).status,
      'superseded by poll-only-governs-watching',
    );
    expect(parseEntry(pollOnly.path).status, 'accepted');

    final marker = docket.entry(
      'docket-2026-01-06',
      day: 6,
      decisionMakers: const ['nico', 'ratify'],
      surfaces: const ['docs/decisions/**'],
    );
    expect(parseEntry(marker.path).decisionMakers, contains('nico'));

    final after = docket.lint;
    expect(after.isClean, isTrue, reason: '${after.toJson()}');

    final markerPattern = RegExp(
      r'^\s*slug:\s*docket-\d{4}-\d{2}-\d{2}\s*$',
      multiLine: true,
    );
    expect(
      docket.register
          .listSync()
          .whereType<File>()
          .where((file) => markerPattern.hasMatch(file.readAsStringSync()))
          .map((file) => p.basename(file.path))
          .toList(),
      ['2026-01-06-docket-2026-01-06.md'],
    );
  });

  test('two unsettled force requests are refused loudly, changing nothing', () {
    final docket = _Docket();
    addTearDown(docket.dispose);
    final targetOne = docket.entry('target-one', day: 1);
    docket.entry('request-one', day: 2, obsoletes: const ['target-one']);
    final targetTwo = docket.entry('target-two', day: 3);
    docket.entry('request-two', day: 4, obsoletes: const ['target-two']);
    final beforeOne = targetOne.readAsBytesSync();
    final beforeTwo = targetTwo.readAsBytesSync();

    expect(
      () => const DecisionMutationService().obsolete(
        registerPath: docket.register.path,
        repoRoot: docket.root.path,
        target: 'target-one',
        successor: 'request-one',
      ),
      throwsA(
        isA<DecisionMutationException>().having(
          (error) => error.message,
          'message',
          contains('candidate register is not clean'),
        ),
      ),
    );
    expect(targetOne.readAsBytesSync(), orderedEquals(beforeOne));
    expect(targetTwo.readAsBytesSync(), orderedEquals(beforeTwo));
    expect(
      _skill,
      contains(
        'reporting `candidate register is not clean: <rules>` and changing no '
        'file',
      ),
    );
  });

  test('the pack declares ratify as the operator-facing docket skill', () {
    final manifest =
        loadYaml(
              File(
                p.join(_packageRoot.path, 'extension', 'mcp', 'config.yaml'),
              ).readAsStringSync(),
            )
            as YamlMap;
    final ratify = (manifest['skills'] as YamlList).cast<YamlMap>().singleWhere(
      (skill) => skill['id'] == 'ratify',
    );
    expect(ratify['audience'], 'operator');
    expect(ratify['path'], 'station_overlay/claude/skills/ratify/SKILL.md');
    expect(
      File(
        p.join(
          _packageRoot.path,
          'extension',
          'station_overlay',
          'claude',
          'skills',
          'ratify',
          'SKILL.md',
        ),
      ).readAsBytesSync(),
      _canonicalSkill.readAsBytesSync(),
    );
  });
}
