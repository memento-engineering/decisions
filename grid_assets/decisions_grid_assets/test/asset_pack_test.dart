import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:decisions_grid_assets/decisions_grid_assets.dart';
import 'package:grid_assets/grid_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

final Directory _packageRoot = Directory.current;
final Directory _repoRoot = Directory(
  p.normalize(p.join(_packageRoot.path, '..', '..')),
);
final Directory _extensionRoot = Directory(
  p.join(_packageRoot.path, 'extension'),
);
final Directory _canonicalSkills = Directory(p.join(_repoRoot.path, 'skills'));
final Directory _generatedSkills = Directory(
  p.join(_extensionRoot.path, 'station_overlay', '.claude', 'skills'),
);
final Directory _canonicalRubrics = Directory(
  p.join(_repoRoot.path, 'rubrics'),
);
final Directory _generatedRubrics = Directory(
  p.join(_extensionRoot.path, 'rubrics'),
);
final Directory _stationOverlay = Directory(
  p.join(_extensionRoot.path, 'station_overlay'),
);
final Directory _decisionAlignmentFixtures = Directory(
  p.join(_packageRoot.path, 'test', 'fixtures', 'decision_alignment'),
);

List<String> _realRelativeFiles(Directory root) {
  if (!root.existsSync()) return const <String>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => p.basename(file.path) != '.PLACEHOLDER')
          .map((file) => p.relative(file.path, from: root.path))
          .toList(growable: false)
        ..sort();
  return files;
}

void _expectGeneratedTreeMatches({
  required Directory canonical,
  required Directory generated,
}) {
  final canonicalFiles = _realRelativeFiles(canonical);
  expect(_realRelativeFiles(generated), canonicalFiles);
  for (final relativePath in canonicalFiles) {
    expect(
      File(p.join(generated.path, relativePath)).readAsBytesSync(),
      File(p.join(canonical.path, relativePath)).readAsBytesSync(),
      reason: relativePath,
    );
  }
}

YamlMap _manifest() =>
    loadYaml(
          File(
            p.join(_extensionRoot.path, 'mcp', 'config.yaml'),
          ).readAsStringSync(),
        )
        as YamlMap;

List<Map<Object?, Object?>> _manifestSkills(YamlMap manifest) {
  final value = manifest['skills'];
  expect(value, isA<YamlList>());
  return [
    for (final item in value as YamlList)
      Map<Object?, Object?>.from(item as YamlMap),
  ];
}

List<Map<Object?, Object?>> _manifestResources(YamlMap manifest) {
  final value = manifest['resources'];
  expect(value, isA<YamlList>());
  return [
    for (final item in value as YamlList)
      Map<Object?, Object?>.from(item as YamlMap),
  ];
}

File _fixtureSpec(String name) =>
    File(p.join(_decisionAlignmentFixtures.path, 'specs', name));

String _fixtureSurface(String spec) {
  final match = RegExp(r'^- `([^`]+)`', multiLine: true).firstMatch(spec);
  if (match == null) fail('fixture spec has no backticked Touches path');
  return match.group(1)!;
}

Future<List<Map<String, dynamic>>> _governingDecisions(String surface) async {
  final output = StringBuffer();
  final runner = CommandRunner<int>('station', 'fixture')
    ..addCommand(
      buildDecisionsCommand(
        mountedSubstationRoots: () => [
          p.join(_decisionAlignmentFixtures.path, 'registers', 'source_repo'),
          p.join(_decisionAlignmentFixtures.path, 'registers', 'policy_repo'),
        ],
        output: output,
      ),
    );

  expect(await runner.run(['decisions', 'index', '--surface', surface]), 0);
  final payload = jsonDecode(output.toString()) as Map<String, dynamic>;
  return (payload['decisions'] as List<dynamic>).cast<Map<String, dynamic>>();
}

void main() {
  test('manifest paths are literal, complete, and not copied at repo root', () {
    final manifest = _manifest();
    final skills = _manifestSkills(manifest);
    expect(manifest['name'], 'decisions_grid_assets');

    final declaredPaths = <String>{};
    for (final skill in skills) {
      expect(skill.keys.map((key) => '$key').toSet(), {
        'id',
        'audience',
        'path',
      });
      final id = skill['id'] as String;
      final audience = skill['audience'] as String;
      final path = skill['path'] as String;
      expect(audience, anyOf('operator', 'agent'));
      expect(path, 'station_overlay/.claude/skills/$id/SKILL.md');
      expect(declaredPaths.add(path), isTrue, reason: 'duplicate $path');
      expect(
        File(p.joinAll([_extensionRoot.path, ...path.split('/')])).existsSync(),
        isTrue,
        reason: path,
      );
    }

    final generatedSkillPaths = {
      for (final relativePath in _realRelativeFiles(_generatedSkills))
        if (p.basename(relativePath) == 'SKILL.md')
          'station_overlay/.claude/skills/'
              '${relativePath.split(p.separator).join('/')}',
    };
    expect(declaredPaths, generatedSkillPaths);

    for (final skillDirectory
        in _canonicalSkills.listSync().whereType<Directory>()) {
      final id = p.basename(skillDirectory.path);
      expect(
        Directory(p.join(_repoRoot.path, '.claude', 'skills', id)).existsSync(),
        isFalse,
        reason: 'canonical skill $id must not have a repository-root copy',
      );
    }
  });

  test('canonical skill tree mirrors generated overlay byte for byte', () {
    final canonicalFiles = _realRelativeFiles(_canonicalSkills);
    if (canonicalFiles.isEmpty) {
      expect(
        _realRelativeFiles(_generatedSkills),
        isEmpty,
        reason: 'placeholder-only canonical tree vends no skill content',
      );
    }
    _expectGeneratedTreeMatches(
      canonical: _canonicalSkills,
      generated: _generatedSkills,
    );
  });

  test('byte sweep accepts a mirror and rejects a mismatch', () {
    final temp = Directory.systemTemp.createTempSync('decisions-overlay-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final canonical = Directory(p.join(temp.path, 'canonical'));
    final generated = Directory(p.join(temp.path, 'generated'));
    final source = File(p.join(canonical.path, 'decide', 'SKILL.md'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([0, 1, 2, 255]);
    final target = File(p.join(generated.path, 'decide', 'SKILL.md'));
    target.parent.createSync(recursive: true);
    source.copySync(target.path);

    expect(
      () => _expectGeneratedTreeMatches(
        canonical: canonical,
        generated: generated,
      ),
      returnsNormally,
    );

    target.writeAsBytesSync([0, 1, 2, 254]);
    expect(
      () => _expectGeneratedTreeMatches(
        canonical: canonical,
        generated: generated,
      ),
      throwsA(isA<TestFailure>()),
    );
  });

  test('overlay installer materializes a skill into the target', () async {
    final temp = Directory.systemTemp.createTempSync('decisions-install-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final overlay = Directory(p.join(temp.path, 'station_overlay'));
    final source =
        File(p.join(overlay.path, '.claude', 'skills', 'fixture', 'SKILL.md'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            '---\n'
            'name: fixture\n'
            'description: Installer fixture.\n'
            '---\n'
            '\n'
            'Fixture body.\n',
          );
    final target = Directory(p.join(temp.path, 'target'))
      ..createSync(recursive: true);

    final report = await const OverlayInstallService().install(
      overlayRoots: [overlay.path],
      targetRoot: target.path,
      sourceRef: 'fixture-ref',
    );

    expect(report.exitCode, 0);
    expect(report.written, hasLength(1));
    final installed = File(
      p.join(target.path, '.claude', 'skills', 'fixture', 'SKILL.md'),
    ).readAsStringSync();
    expect(installed, contains('generated from grid_assets@fixture-ref'));
    expect(installed, contains('Fixture body.'));
    expect(source.readAsStringSync(), isNot(contains('generated from')));
  });

  test('canonical decision-alignment rubric is vended byte for byte', () {
    final resources = _manifestResources(_manifest());
    expect(resources, hasLength(1));
    expect(resources.single, {
      'id': 'decision-alignment',
      'description':
          'Grades a spec against the roster-wide union of decisions '
          'governing its touched surfaces.',
      'path': 'rubrics/decision-alignment.md',
      'visibility': 'public',
    });

    _expectGeneratedTreeMatches(
      canonical: _canonicalRubrics,
      generated: _generatedRubrics,
    );
    final canonical = File(
      p.join(_canonicalRubrics.path, 'decision-alignment.md'),
    );
    final generated = File(
      p.join(_generatedRubrics.path, 'decision-alignment.md'),
    );
    expect(generated.readAsBytesSync(), canonical.readAsBytesSync());
  });

  test('decision-alignment lookup and bands follow the register contract', () {
    final rubric = File(
      p.join(_generatedRubrics.path, 'decision-alignment.md'),
    ).readAsStringSync();

    expect(
      rubric,
      contains('<station> decisions index --surface <repo>/<path>'),
    );
    expect(rubric, contains('with no explicit register-directory arguments'));
    expect(rubric, contains('docs/decisions/'));
    expect(rubric, isNot(contains('docs/adr/')));
    expect(
      rubric,
      contains('Every recorded decision binds. There is no pending state.'),
    );
    for (final band in ['**A**', '**B**', '**C**', '**D**', '**F**']) {
      expect(rubric, contains(band), reason: band);
    }
    expect(rubric, contains('load-bearing'));
    expect(rubric, contains('structural contradiction'));
  });

  test(
    'sibling-register contradiction fixture is F with offending slug',
    () async {
      final spec = _fixtureSpec('contradicts_sibling.md').readAsStringSync();
      final decisions = await _governingDecisions(_fixtureSurface(spec));

      expect(spec, contains('Directory.watch'));
      expect(decisions, hasLength(1));
      expect(decisions.single['originRegister'], 'policy_repo');
      expect(decisions.single['slug'], 'no-file-watching');
      final policy = File(
        p.join(
          _decisionAlignmentFixtures.path,
          'registers',
          'policy_repo',
          'docs',
          'decisions',
          '2026-01-01-no-file-watching.md',
        ),
      ).readAsStringSync();
      expect(policy, contains('Do not introduce file-system watchers'));

      final rubric = File(
        p.join(_generatedRubrics.path, 'decision-alignment.md'),
      ).readAsStringSync();
      expect(
        rubric,
        contains('grade **F** and cite `policy_repo#no-file-watching`'),
      );
    },
  );

  test('ungoverned surface fixture has no citation penalty', () async {
    final spec = _fixtureSpec('ungoverned_surface.md').readAsStringSync();
    final decisions = await _governingDecisions(_fixtureSurface(spec));

    expect(decisions, isEmpty);
    expect(spec, contains('No decision applies'));
    final rubric = File(
      p.join(_generatedRubrics.path, 'decision-alignment.md'),
    ).readAsStringSync();
    expect(rubric, contains('must not be penalised for citing no decision'));
    expect(rubric, contains('no-precedent form of grade **A**'));
  });

  test('station_overlay vends only frontmatter-led installable assets', () {
    final files = _realRelativeFiles(_stationOverlay);
    expect(files, isNotEmpty);
    for (final relativePath in files) {
      final segments = p.split(relativePath);
      expect(
        segments.length >= 2 &&
            segments.first == '.claude' &&
            (segments[1] == 'skills' || segments[1] == 'agents'),
        isTrue,
        reason:
            'the overlay installs skills and agent defs only — move '
            '"$relativePath" out of station_overlay',
      );
      final body = File(
        p.join(_stationOverlay.path, relativePath),
      ).readAsStringSync();
      expect(
        provenanceSyntaxFor(relativePath, body),
        isA<YamlFrontmatterProvenance>(),
        reason: 'unstampable overlay file: $relativePath',
      );
    }
  });

  test('every declared resource resolves outside the station overlay', () {
    final resources = _manifestResources(_manifest());
    expect(resources, isNotEmpty);
    for (final resource in resources) {
      expect(resource.keys.map((key) => '$key').toSet(), {
        'id',
        'description',
        'path',
        'visibility',
      });
      final id = resource['id'] as String;
      final path = resource['path'] as String;
      expect(path, 'rubrics/$id.md');
      expect(
        path.startsWith('station_overlay/'),
        isFalse,
        reason: 'a rubric is read at critique time, never installed: $path',
      );
      expect(
        File(p.joinAll([_extensionRoot.path, ...path.split('/')])).existsSync(),
        isTrue,
        reason: path,
      );
    }
  });

  test('packaged loader resolves the rubric by id', () {
    final loader = PackagedAssetLoader(root: _extensionRoot.path);
    expect(
      loader.loadRubric('decision-alignment'),
      File(
        p.join(_canonicalRubrics.path, 'decision-alignment.md'),
      ).readAsStringSync().trim(),
    );
  });

  test('installing this pack overlay vends the stamped decide skill', () async {
    final target = Directory.systemTemp.createTempSync('decisions-vend-');
    addTearDown(() => target.deleteSync(recursive: true));

    final report = await const OverlayInstallService().install(
      overlayRoots: [_stationOverlay.path],
      targetRoot: target.path,
      sourceRef: 'fixture-ref',
    );

    expect(report.exitCode, 0);
    expect(report.written.map((file) => file.relativePath).toList(), [
      p.join('.claude', 'skills', 'decide', 'SKILL.md'),
    ]);
    final installed = File(
      p.join(target.path, '.claude', 'skills', 'decide', 'SKILL.md'),
    ).readAsStringSync();
    expect(installed, contains('generated from grid_assets@fixture-ref'));
    expect(installed, contains('name: decide'));
  });
}
