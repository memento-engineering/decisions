import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The vended action and the release workflow, relative to the package root.
const _actionPath = '../../../.github/actions/lint-gate/action.yml';
const _releasePath = '../../../.github/workflows/release.yaml';

YamlMap _load(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

void main() {
  group('the lint-gate action', () {
    late YamlMap action;
    late YamlMap inputs;
    late YamlList steps;
    late String script;

    setUp(() {
      action = _load(_actionPath);
      inputs = action['inputs'] as YamlMap;
      steps = (action['runs'] as YamlMap)['steps'] as YamlList;
      script = (steps.single as YamlMap)['run'] as String;
    });

    test('takes a required version and defaulted register paths', () {
      expect(
        inputs.keys,
        unorderedEquals(['version', 'register', 'repo-root']),
      );
      expect((inputs['version'] as YamlMap)['required'], isTrue);
      expect((inputs['register'] as YamlMap)['default'], 'docs/decisions');
      expect((inputs['repo-root'] as YamlMap)['default'], '.');
    });

    test('is one composite bash step that uses no other action', () {
      expect((action['runs'] as YamlMap)['using'], 'composite');
      final step = steps.single as YamlMap;
      expect(step['shell'], 'bash');
      expect(step.containsKey('uses'), isFalse);
      expect(script, contains('set -euo pipefail'));
    });

    test('downloads the release asset and its SHA256SUMS', () {
      expect(
        script,
        contains(
          'https://github.com/memento-engineering/decisions/releases/download/'
          'decisions-v\$DECISIONS_VERSION',
        ),
      );
      expect(
        script,
        contains('asset="decisions-\$DECISIONS_VERSION-\$target"'),
      );
      expect(script, contains('SHA256SUMS'));
      for (final target in ['linux-x64', 'linux-arm64', 'macos-arm64']) {
        expect(script, contains('target=$target'));
      }
      expect(script, contains('no decisions binary for'));
    });

    test('verifies the binary before it runs it', () {
      final linux = script.indexOf('sha256sum -c -');
      final macos = script.indexOf('shasum -a 256 -c -');
      final gate = script.indexOf('lint --gate');

      expect(linux, isNonNegative);
      expect(macos, isNonNegative);
      expect(gate, greaterThan(linux));
      expect(gate, greaterThan(macos));
    });

    test('runs lint --gate over the inputs, with no Dart', () {
      expect(
        script,
        contains(
          'lint --gate "\$DECISIONS_REGISTER" '
          '--repo-root "\$DECISIONS_REPO_ROOT"',
        ),
      );
      expect(script, isNot(matches(RegExp(r'\bdart\b'))));
      expect(
        File(_actionPath).readAsStringSync(),
        isNot(contains('setup-dart')),
      );
    });
  });

  group('release.yaml register_gate_published', () {
    late YamlMap job;

    setUp(() {
      final jobs = _load(_releasePath)['jobs'] as YamlMap;
      job = jobs['register_gate_published'] as YamlMap;
    });

    test('runs after the release', () {
      expect(job['needs'], 'release');
    });

    test('runs the vended action with the tag\'s version and no Dart', () {
      final steps = (job['steps'] as YamlList).cast<YamlMap>();
      final gate = steps.singleWhere(
        (step) => step['uses'] == './.github/actions/lint-gate',
      );
      final version = steps.singleWhere((step) => step['id'] == 'version');

      expect(version['run'], contains(r'${GITHUB_REF_NAME#decisions-v}'));
      expect(
        (gate['with'] as YamlMap)['version'],
        r'${{ steps.version.outputs.version }}',
      );
      expect(
        steps.where((step) => '${step['uses'] ?? ''}'.contains('setup-dart')),
        isEmpty,
      );
    });
  });
}
