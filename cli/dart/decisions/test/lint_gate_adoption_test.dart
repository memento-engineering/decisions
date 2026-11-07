import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The vended action and the release workflow, relative to the package root.
const _actionPath = '../../../.github/actions/lint-gate/action.yml';
const _releasePath = '../../../.github/workflows/release.yaml';

/// The user docs that tell a repository owner how to adopt the gate.
const _packReadmePath = '../../../gc_pack/decisions/README.md';
const _readmePath = '../../../README.md';
const _agentsPath = '../../../AGENTS.md';

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

  group('adoption docs', () {
    late String pack;

    setUp(() => pack = File(_packReadmePath).readAsStringSync());

    test('the pack README gives the job to copy', () {
      final section = pack.substring(
        pack.indexOf('\n## Gate the register in CI\n'),
      );

      expect(
        section,
        contains(
          'uses: memento-engineering/decisions/.github/actions/lint-gate'
          '@decisions-v',
        ),
      );
      expect(section, contains('version: '));
      expect(section, contains('decisions lint --gate docs/decisions'));
      expect(section, contains('roster:'));
      expect(section, contains('--gate'));
      expect(pack, isNot(contains('setup-dart')));
    });

    test('the doctor section points at the gate section', () {
      final doctor = pack.substring(
        pack.indexOf('\n## The doctor check\n'),
        pack.indexOf('\n## Gate the register in CI\n'),
      );

      expect(doctor, contains('(#gate-the-register-in-ci)'));
    });

    test('the root README points at it from the exit codes', () {
      final readme = File(_readmePath).readAsStringSync();

      expect(readme, contains('decisions lint --gate'));
      expect(
        readme,
        contains('(gc_pack/decisions/README.md#gate-the-register-in-ci)'),
      );
    });

    test('AGENTS.md names the action and its post-release job', () {
      final agents = File(_agentsPath).readAsStringSync();

      expect(agents, contains('`.github/actions/lint-gate/`'));
      expect(agents, contains('`register_gate_published`'));
    });

    test('the pack still ships no orders', () {
      expect(
        Directory('../../../gc_pack/decisions/orders').existsSync(),
        false,
      );
    });
  });
}
