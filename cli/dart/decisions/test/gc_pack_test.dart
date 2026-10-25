@TestOn('!windows')
library;

import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The Gas City pack, relative to the package root.
const _pack = '../../../gc_pack/decisions';

/// The pack root as gc hands it to a doctor script in `GC_PACK_DIR`.
final _packDir = p.normalize(p.absolute(_pack));

/// The doctor shim gc runs as `decisions:binary`.
final _shim = p.join(_packDir, 'doctor', 'binary', 'run.sh');

/// Every file under [root], as sorted paths relative to it.
List<String> _files(String root) => [
  for (final entity in Directory(root).listSync(recursive: true))
    if (entity is File) p.relative(entity.path, from: root),
]..sort();

void main() {
  group('skills', () {
    late Directory sandbox;

    setUp(() => sandbox = Directory.systemTemp.createTempSync('gc-pack-'));
    tearDown(() => sandbox.deleteSync(recursive: true));

    test(
      'are exactly what skills install writes (regenerate: see AGENTS.md)',
      () async {
        final expected = p.join(sandbox.path, 'skills');
        final code = await DecisionsCommandRunner(
          output: StringBuffer(),
          error: StringBuffer(),
        ).run(['skills', 'install', expected]);
        expect(code, 0);

        final committed = p.join(_pack, 'skills');
        expect(_files(committed), _files(expected));
        for (final file in _files(expected)) {
          expect(
            File(p.join(committed, file)).readAsStringSync(),
            File(p.join(expected, file)).readAsStringSync(),
            reason: file,
          );
        }
      },
    );

    test('each defers to `decisions guide <name>`', () {
      for (final guide in bundledGuides) {
        final stub = File(
          p.join(_pack, 'skills', guide.name, 'SKILL.md'),
        ).readAsStringSync();
        expect(stub, contains('Run `decisions guide ${guide.name}`'));
      }
    });
  });

  test('the pack holds only the files the pack spec allows', () {
    expect(
      _files(_pack),
      [
        'README.md',
        p.join('doctor', 'binary', 'doctor.toml'),
        p.join('doctor', 'binary', 'run.sh'),
        'pack.toml',
        for (final guide in bundledGuides)
          p.join('skills', guide.name, 'SKILL.md'),
      ]..sort(),
    );
  });

  test('pack.toml is the three-key schema-2 manifest', () {
    final lines = File(p.join(_pack, 'pack.toml'))
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();

    expect(lines, hasLength(4));
    expect(lines.take(3), ['[pack]', 'name = "decisions"', 'schema = 2']);
    expect(lines.last, matches(RegExp(r'^description = "[^"\\]+"$')));
  });

  test('doctor.toml describes the check and runs it at warm-up', () {
    final lines = File(
      p.join(_pack, 'doctor', 'binary', 'doctor.toml'),
    ).readAsLinesSync().where((line) => line.trim().isNotEmpty).toList();

    expect(lines, hasLength(2));
    expect(lines.first, matches(RegExp(r'^description = "[^"\\]+"$')));
    expect(lines.last, 'warmup = true');
  });

  group('the doctor shim', () {
    late Directory sandbox;
    late String fakeDir;
    late String argvFile;

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('gc-pack-shim-');
      fakeDir = p.join(sandbox.path, 'bin');
      argvFile = p.join(sandbox.path, 'argv');
      Directory(fakeDir).createSync();
    });

    tearDown(() => sandbox.deleteSync(recursive: true));

    /// Installs a fake `decisions` that records its argv, one per line, and
    /// answers with [stdout], a line of stderr noise and [exitCode].
    Future<void> fakeDecisions({
      required String stdout,
      required int exitCode,
    }) async {
      final fake = File(p.join(fakeDir, 'decisions'))
        ..writeAsStringSync('''
#!/bin/sh
printf '%s\\n' "\$@" > '$argvFile'
printf '%s' '$stdout'
printf 'fake decisions stderr noise\\n' >&2
exit $exitCode
''');
      final chmod = await Process.run('chmod', ['+x', fake.path]);
      expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
    }

    /// Runs the shim directly, as gc's `exec.Command(script)` does: cwd the
    /// pack, city-only env, and a PATH of [path].
    Future<ProcessResult> runShim({
      required String path,
      bool withPackDir = true,
    }) => Process.run(
      _shim,
      const [],
      workingDirectory: _packDir,
      environment: {
        'PATH': path,
        'GC_PACK_DIR': ?(withPackDir ? _packDir : null),
      },
      includeParentEnvironment: false,
    );

    String firstLine(ProcessResult result) =>
        (result.stdout as String).split('\n').first;

    test('is a #!/bin/sh script with its exec bits set', () {
      expect(File(_shim).readAsStringSync(), startsWith('#!/bin/sh\n'));
      expect(File(_shim).statSync().mode & 0x49, 0x49); // 0o111
    });

    test('fails, naming the binary, when decisions is not on PATH', () async {
      final result = await runShim(path: '/usr/bin:/bin');

      expect(result.exitCode, 2);
      expect(firstLine(result), 'decisions not found on PATH');
      expect(result.stdout, contains('brew install'));
    });

    for (final code in [0, 1, 2]) {
      test('passes exit $code and stdout through, without stderr', () async {
        const report = 'worst finding line (and 1 more)\n  detail line\n';
        await fakeDecisions(stdout: report, exitCode: code);

        final result = await runShim(path: '$fakeDir:/usr/bin:/bin');

        expect(result.exitCode, code);
        expect(result.stdout, report);
        expect(result.stderr, isEmpty);
      });
    }

    for (final code in [64, 255]) {
      test(
        'maps exit $code from a binary without doctor to a failure',
        () async {
          await fakeDecisions(stdout: 'usage noise\n', exitCode: code);

          final result = await runShim(path: '$fakeDir:/usr/bin:/bin');

          expect(result.exitCode, 2);
          expect(
            firstLine(result),
            'decisions at ${p.join(fakeDir, 'decisions')} cannot run doctor '
            '(exit $code); it predates this pack',
          );
          expect(result.stdout, isNot(contains('noise')));
          expect(result.stderr, isEmpty);
        },
      );
    }

    test('asks doctor for the binary and this pack\'s stubs only', () async {
      await fakeDecisions(stdout: 'ok\n', exitCode: 0);

      await runShim(path: '$fakeDir:/usr/bin:/bin');

      expect(File(argvFile).readAsLinesSync(), [
        'doctor',
        '--no-register',
        '--skills',
        p.join(_packDir, 'skills'),
      ]);
    });

    test('finds the pack from its own path without GC_PACK_DIR', () async {
      await fakeDecisions(stdout: 'ok\n', exitCode: 0);

      await runShim(path: '$fakeDir:/usr/bin:/bin', withPackDir: false);

      final skills = File(argvFile).readAsLinesSync().last;
      expect(
        Directory(skills).resolveSymbolicLinksSync(),
        Directory(p.join(_packDir, 'skills')).resolveSymbolicLinksSync(),
      );
    });
  });
}
