import 'dart:io';

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

void _expectGeneratedSkillsMatch({
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
    _expectGeneratedSkillsMatch(
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
      () => _expectGeneratedSkillsMatch(
        canonical: canonical,
        generated: generated,
      ),
      returnsNormally,
    );

    target.writeAsBytesSync([0, 1, 2, 254]);
    expect(
      () => _expectGeneratedSkillsMatch(
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
}
