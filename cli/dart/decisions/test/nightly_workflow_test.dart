import 'dart:convert';
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

const _nightlyPath = '../../../.github/workflows/nightly.yaml';

/// A parsed YAML or JSON mapping.
typedef _Json = Map<Object?, Object?>;

YamlMap _load(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

/// [path] parsed into plain, mutable Dart maps and lists, so a test can
/// break a copy of it.
Map<String, Object?> _loadPlain(String path) =>
    jsonDecode(jsonEncode(_load(path))) as Map<String, Object?>;

/// The steps of [job] in [workflow].
List<_Json> _steps(_Json workflow, String job) =>
    (((workflow['jobs'] as _Json)[job] as _Json)['steps'] as List)
        .cast<_Json>();

/// The index of the one step of [steps] that uses the shared tools action.
int _toolsStepIndex(List<_Json> steps) {
  final indexes = [
    for (var i = 0; i < steps.length; i++)
      if (steps[i]['uses'] == _toolsUses) i,
  ];
  expect(indexes, hasLength(1), reason: 'one step uses $_toolsUses');
  return indexes.single;
}

/// A line that invokes `gc_pack/e2e.sh` as the command, not as an argument
/// to another tool such as `shellcheck`.
final _e2eInvocation = RegExp(r'^\s*gc_pack/e2e\.sh\s*$', multiLine: true);

/// What is wrong with [nightly] as the gc-latest e2e run; empty when nothing
/// is.
List<String> _nightlyProblems(_Json nightly) {
  final problems = <String>[];
  final on = nightly['on'] as _Json;
  if (on.containsKey('push') || on.containsKey('pull_request')) {
    problems.add('it triggers on push or pull_request');
  }
  if (!on.containsKey('workflow_dispatch')) {
    problems.add('it has no workflow_dispatch');
  }
  final schedule = on['schedule'] as List?;
  if (schedule == null || schedule.length != 1) {
    problems.add('it has not exactly one schedule');
  } else {
    final fields = ((schedule.single as _Json)['cron'] as String).split(' ');
    final daily =
        fields.length == 5 &&
        int.tryParse(fields[0]) != null &&
        int.tryParse(fields[1]) != null &&
        fields.skip(2).every((field) => field == '*');
    if (!daily) problems.add('its cron is not once a day: $fields');
  }
  final permissions = nightly['permissions'];
  if (permissions is! _Json ||
      permissions.length != 1 ||
      permissions['contents'] != 'read') {
    problems.add('its permissions are not exactly contents: read');
  }
  final jobs = nightly['jobs'] as _Json;
  if (jobs.keys.toList().join(',') != 'gc_pack_latest') {
    problems.add('its jobs are not exactly gc_pack_latest: ${jobs.keys}');
    return problems;
  }
  final job = jobs['gc_pack_latest'] as _Json;
  if (job['runs-on'] != 'ubuntu-24.04') {
    problems.add('gc_pack_latest runs on ${job['runs-on']}');
  }
  final steps = (job['steps'] as List).cast<_Json>();
  final tools = steps.indexWhere((step) => step['uses'] == _toolsUses);
  if (tools < 0) {
    problems.add('no step uses $_toolsUses');
    return problems;
  }
  if ((steps[tools]['with'] as _Json?)?['gc-version'] != 'latest') {
    problems.add('the tools step does not set gc-version: latest');
  }
  final e2e = steps.indexWhere(
    (step) => _e2eInvocation.hasMatch((step['run'] as String?) ?? ''),
  );
  if (e2e < 0) {
    problems.add('no step runs gc_pack/e2e.sh');
  } else if (e2e < tools) {
    problems.add('gc_pack/e2e.sh runs before the tools step');
  } else {
    final run = steps[e2e]['run'] as String;
    for (final bin in ['GC_BIN', 'BD_BIN', 'DOLT_BIN', 'DECISIONS_BIN']) {
      if (!run.contains('$bin="\$RUNNER_TEMP/bin/')) {
        problems.add('the e2e step does not point $bin at the tools');
      }
    }
  }
  return problems;
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
        final inputs = tools['with'] as _Json?;
        expect(inputs?.containsKey('gc-version') ?? false, isFalse);
      });
    }
  });

  group('the nightly workflow', () {
    late Map<String, Object?> nightly;

    setUp(() => nightly = _loadPlain(_nightlyPath));

    test('runs the pack e2e daily against gc latest, and only that', () {
      expect(_nightlyProblems(nightly), isEmpty);
      // The facts the problems check, stated directly.
      final on = nightly['on'] as _Json;
      expect(on.keys, unorderedEquals(['schedule', 'workflow_dispatch']));
      expect(nightly['permissions'], {'contents': 'read'});
      expect((nightly['jobs'] as _Json).keys, ['gc_pack_latest']);
      final steps = _steps(nightly, 'gc_pack_latest');
      expect(steps[_toolsStepIndex(steps)]['with'], {
        'apt-extra': 'shellcheck',
        'gc-version': 'latest',
      });
    });

    test('repeats the gc_pack steps of ci.yaml with only gc-version added', () {
      final pinned = _steps(_loadPlain(_ciPath), 'gc_pack');
      final latest = _steps(nightly, 'gc_pack_latest');
      final tools = _toolsStepIndex(latest);
      final withoutGcVersion = [
        for (final (i, step) in latest.indexed)
          if (i == tools)
            {
              ...step,
              'with': {...(step['with'] as _Json)}..remove('gc-version'),
            }
          else
            step,
      ];
      expect(withoutGcVersion, pinned);
    });

    group('fails a nightly that', () {
      List<_Json> stepsOf(Map<String, Object?> workflow) =>
          _steps(workflow, 'gc_pack_latest');

      test('runs e2e before the tools step', () {
        final steps = stepsOf(nightly);
        final e2e = steps.lastWhere(
          (step) => _e2eInvocation.hasMatch((step['run'] as String?) ?? ''),
        );
        steps
          ..remove(e2e)
          ..insert(0, e2e);
        expect(
          _nightlyProblems(nightly),
          contains('gc_pack/e2e.sh runs before the tools step'),
        );
      });

      test('omits gc-version on the tools step', () {
        final steps = stepsOf(nightly);
        (steps[_toolsStepIndex(steps)]['with'] as _Json).remove('gc-version');
        expect(
          _nightlyProblems(nightly),
          contains('the tools step does not set gc-version: latest'),
        );
      });

      test('only shellchecks e2e and never runs it', () {
        final steps = stepsOf(nightly);
        steps.removeWhere(
          (step) => _e2eInvocation.hasMatch((step['run'] as String?) ?? ''),
        );
        expect(
          steps.any((step) => step['run'] == 'shellcheck gc_pack/e2e.sh'),
          isTrue,
        );
        expect(
          _nightlyProblems(nightly),
          contains('no step runs gc_pack/e2e.sh'),
        );
      });

      test('runs more often than once a day', () {
        ((nightly['on'] as _Json)['schedule'] as List).single['cron'] =
            '* * * * *';
        expect(_nightlyProblems(nightly), hasLength(1));
      });

      test('also triggers on push', () {
        (nightly['on'] as _Json)['push'] = {
          'branches': ['main'],
        };
        expect(_nightlyProblems(nightly), hasLength(1));
      });

      test('carries a second job or another runner', () {
        final jobs = nightly['jobs'] as _Json;
        (jobs['gc_pack_latest'] as _Json)['runs-on'] = 'ubuntu-latest';
        expect(_nightlyProblems(nightly), hasLength(1));
        jobs['other'] = {'runs-on': 'ubuntu-24.04', 'steps': <Object>[]};
        expect(_nightlyProblems(nightly), hasLength(1));
      });
    });
  });
}
