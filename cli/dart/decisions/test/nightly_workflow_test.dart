import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The shared tools action and the workflows that use it, relative to the
/// package root.
const _toolsPath = '../../../.github/actions/gc-sandbox-tools/action.yml';
const _ciPath = '../../../.github/workflows/ci.yaml';
const _releasePath = '../../../.github/workflows/release.yaml';

/// How a workflow step names the shared tools action.
const _toolsUses = './.github/actions/gc-sandbox-tools';

YamlMap _load(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

/// The steps of [job] in [workflow].
List<YamlMap> _steps(YamlMap workflow, String job) =>
    (((workflow['jobs'] as YamlMap)[job] as YamlMap)['steps'] as YamlList)
        .cast<YamlMap>();

/// The index of the one step of [steps] that uses the shared tools action.
int _toolsStepIndex(List<YamlMap> steps) {
  final indexes = [
    for (var i = 0; i < steps.length; i++)
      if (steps[i]['uses'] == _toolsUses) i,
  ];
  expect(indexes, hasLength(1), reason: 'one step uses $_toolsUses');
  return indexes.single;
}

void main() {
  group('the gc-sandbox-tools action', () {
    late YamlMap action;
    late YamlMap download;
    late YamlMap env;
    late String script;

    setUp(() {
      action = _load(_toolsPath);
      final steps = ((action['runs'] as YamlMap)['steps'] as YamlList)
          .cast<YamlMap>();
      download = steps.singleWhere((step) => step['id'] == 'download');
      env = download['env'] as YamlMap;
      script = download['run'] as String;
    });

    test('takes a gc-version input that defaults to the pinned version', () {
      final input = (action['inputs'] as YamlMap)['gc-version'] as YamlMap;
      expect(input['default'], '1.5.1');
      expect(input['required'], isFalse);
      expect(env['GC_PINNED_VERSION'].toString(), input['default']);
      expect(env['GC_VERSION_INPUT'], r'${{ inputs.gc-version }}');
      expect(env.containsKey('GC_VERSION'), isFalse);
    });

    test('its download script is valid bash that resolves latest', () async {
      final syntax = await Process.run('bash', ['-n', '-c', script]);
      expect(syntax.exitCode, 0, reason: '${syntax.stderr}');
      expect(script, contains('releases/latest'));
    });

    test('checks the pinned sha256 only for the pinned version', () {
      final pinnedCheck = script.indexOf(r'echo "${GC_SHA256}  $gc_tar"');
      final guard = script.indexOf(r'if [ "$gc_pinned" = true ]; then');
      final checksums = script.indexOf(r'grep " $gc_tar\$" "gascity_');
      expect(guard, isNonNegative);
      expect(pinnedCheck, greaterThan(guard));
      expect(checksums, greaterThan(pinnedCheck));
    });

    test('refuses an unknown gc-version before any download', () async {
      final temp = await Directory.systemTemp.createTemp('gc-sandbox-tools');
      addTearDown(() => temp.delete(recursive: true));
      final runnerTemp = await Directory(p.join(temp.path, 'runner')).create();
      final githubPath = File(p.join(temp.path, 'github_path'))..createSync();
      final githubOutput = File(p.join(temp.path, 'github_output'))
        ..createSync();
      // Stand-ins for every network tool the script could call: each leaves
      // a mark, so a download attempted before the refusal is seen.
      final stubs = await Directory(p.join(temp.path, 'stubs')).create();
      final marks = p.join(temp.path, 'marks');
      for (final tool in ['curl', 'gh']) {
        final stub = File(p.join(stubs.path, tool))
          ..writeAsStringSync('#!/bin/sh\necho "$tool" >> "$marks"\nexit 1\n');
        await Process.run('chmod', ['+x', stub.path]);
      }

      final stepEnv = <String, String>{
        for (final MapEntry(:key, :value) in env.entries)
          key as String: value.toString().contains(r'${{')
              ? ''
              : value.toString(),
      };
      final result = await Process.run(
        'bash',
        ['-c', script],
        environment: {
          ...stepEnv,
          'GC_VERSION_INPUT': '2.0.0',
          'RUNNER_TEMP': runnerTemp.path,
          'GITHUB_PATH': githubPath.path,
          'GITHUB_OUTPUT': githubOutput.path,
          'PATH': '${stubs.path}:${Platform.environment['PATH']}',
        },
      );

      expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
      final refusal = (result.stderr as String)
          .split('\n')
          .where((line) => line.contains('gc-version'));
      expect(refusal, isNotEmpty, reason: '${result.stderr}');
      expect(refusal.first, allOf(contains('1.5.1'), contains('latest')));
      expect(File(p.join(runnerTemp.path, 'bin', 'gc')).existsSync(), isFalse);
      expect(File(marks).existsSync(), isFalse, reason: 'nothing downloads');
      expect(githubPath.readAsStringSync(), isEmpty);
    });
  });

  group('the gated gc_pack jobs stay on the pinned gc', () {
    for (final (path, job) in [
      (_ciPath, 'gc_pack'),
      (_releasePath, 'gc_pack_published'),
    ]) {
      test('$job sets no gc-version', () {
        final steps = _steps(_load(path), job);
        final tools = steps[_toolsStepIndex(steps)];
        final inputs = tools['with'] as YamlMap?;
        expect(inputs?.containsKey('gc-version') ?? false, isFalse);
      });
    }
  });
}
