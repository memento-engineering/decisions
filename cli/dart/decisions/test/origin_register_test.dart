import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A roster that carries exactly [registers], read from no disk.
final class _FakeRoster implements DecisionRoster {
  const _FakeRoster(this.registers);

  @override
  final List<DecisionRegisterSnapshot> registers;

  @override
  DecisionRegisterSnapshot? findRegister(String originRegister) {
    for (final register in registers) {
      if (register.originRegister == originRegister) return register;
    }
    return null;
  }
}

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('decision-origin-register-');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  /// Creates `<sandbox>/<segments>/docs/decisions` and returns its path.
  String registerAt(List<String> segments) {
    final register = Directory(
      p.joinAll([sandbox.path, ...segments, 'docs', 'decisions']),
    )..createSync(recursive: true);
    return register.path;
  }

  /// Creates a main checkout `<sandbox>/<name>` with a `.git` directory.
  String mainCheckout(String name) {
    final root = p.join(sandbox.path, name);
    Directory(p.join(root, '.git', 'worktrees')).createSync(recursive: true);
    return root;
  }

  /// Links the checkout at [checkout] to [main] the way `git worktree add`
  /// does, writing `commondir` unless [withCommonDir] is false.
  void linkWorktree(
    String checkout,
    String main, {
    required String id,
    bool withCommonDir = true,
    bool relativePointer = false,
  }) {
    final gitDir = Directory(p.join(main, '.git', 'worktrees', id))
      ..createSync(recursive: true);
    if (withCommonDir) {
      File(p.join(gitDir.path, 'commondir')).writeAsStringSync('../..\n');
    }
    final pointer = relativePointer
        ? p.relative(gitDir.path, from: checkout)
        : gitDir.path;
    File(p.join(checkout, '.git')).writeAsStringSync('gitdir: $pointer\n');
  }

  group('decisionOriginRegister', () {
    test('a plain register with no git names its repo directory', () {
      expect(decisionOriginRegister(registerAt(['plain'])), 'plain');
    });

    test('a main checkout names its own directory', () {
      mainCheckout('decisions');
      expect(decisionOriginRegister(registerAt(['decisions'])), 'decisions');
    });

    test('a linked worktree with a commondir names the main checkout', () {
      final main = mainCheckout('decisions');
      final register = registerAt([
        'decisions',
        '.claude',
        'worktrees',
        'no-orders',
      ]);
      linkWorktree(p.dirname(p.dirname(register)), main, id: 'no-orders');

      expect(decisionOriginRegister(register), 'decisions');
    });

    test('a linked worktree without a commondir names the main checkout', () {
      final main = mainCheckout('decisions');
      final register = registerAt(['elsewhere', 'scratch']);
      linkWorktree(
        p.dirname(p.dirname(register)),
        main,
        id: 'scratch',
        withCommonDir: false,
      );

      expect(decisionOriginRegister(register), 'decisions');
    });

    test('a relative gitdir pointer resolves against the checkout', () {
      final main = mainCheckout('decisions');
      final register = registerAt(['decisions-copy']);
      linkWorktree(
        p.dirname(p.dirname(register)),
        main,
        id: 'decisions-copy',
        relativePointer: true,
      );

      expect(decisionOriginRegister(register), 'decisions');
    });

    test('an absolute commondir is followed as written', () {
      final main = mainCheckout('decisions');
      final register = registerAt(['wt']);
      final checkout = p.dirname(p.dirname(register));
      linkWorktree(checkout, main, id: 'wt');
      File(
        p.join(main, '.git', 'worktrees', 'wt', 'commondir'),
      ).writeAsStringSync(p.join(main, '.git'));

      expect(decisionOriginRegister(register), 'decisions');
    });

    test('a worktree of a bare repository drops the .git suffix', () {
      final bare = Directory(p.join(sandbox.path, 'decisions.git'))
        ..createSync();
      final gitDir = Directory(p.join(bare.path, 'worktrees', 'wt'))
        ..createSync(recursive: true);
      File(p.join(gitDir.path, 'commondir')).writeAsStringSync('../..\n');
      final register = registerAt(['wt']);
      File(
        p.join(p.dirname(p.dirname(register)), '.git'),
      ).writeAsStringSync('gitdir: ${gitDir.path}\n');

      expect(decisionOriginRegister(register), 'decisions');
    });

    group('a provisioned grid worktree', () {
      test('without a git pointer names the substation', () {
        final register = registerAt([
          'grid',
          '.grid',
          'worktrees',
          'grid',
          'grid-fig',
        ]);
        expect(decisionOriginRegister(register), 'grid');
      });

      test('linked to its repo gives the same name as the substation rule '
          'when the substation is the repo', () {
        final main = mainCheckout('grid');
        final register = registerAt([
          'grid',
          '.grid',
          'worktrees',
          'grid',
          'grid-fig',
        ]);
        linkWorktree(p.dirname(p.dirname(register)), main, id: 'grid-fig');

        expect(decisionOriginRegister(register), 'grid');
      });

      test('linked to its repo names the repo, not a differing substation', () {
        final main = mainCheckout('memento-engineering');
        final register = registerAt([
          'memento-engineering',
          '.grid',
          'worktrees',
          'manual',
          'org-2ra',
        ]);
        linkWorktree(p.dirname(p.dirname(register)), main, id: 'org-2ra');

        expect(decisionOriginRegister(register), 'memento-engineering');
      });
    });

    group('a .git file it cannot follow falls back to the directory', () {
      late String register;
      late File dotGit;

      setUp(() {
        register = registerAt(['broken']);
        dotGit = File(p.join(p.dirname(p.dirname(register)), '.git'));
      });

      test('when empty', () {
        dotGit.writeAsStringSync('');
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when it carries no gitdir line', () {
        dotGit.writeAsStringSync('not a pointer\n');
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when the gitdir is blank', () {
        dotGit.writeAsStringSync('gitdir:   \n');
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when it is not UTF-8', () {
        dotGit.writeAsBytesSync([0x67, 0x69, 0xff, 0xfe, 0x0a]);
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when it points at a missing directory outside worktrees/', () {
        dotGit.writeAsStringSync(
          'gitdir: ${p.join(sandbox.path, 'gone', '.git')}\n',
        );
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when it points at a submodule git directory', () {
        final modules = Directory(
          p.join(sandbox.path, 'super', '.git', 'modules', 'broken'),
        )..createSync(recursive: true);
        dotGit.writeAsStringSync('gitdir: ${modules.path}\n');
        expect(decisionOriginRegister(register), 'broken');
      });

      test('when the commondir is blank', () {
        final main = mainCheckout('decisions');
        linkWorktree(p.dirname(p.dirname(register)), main, id: 'broken');
        File(
          p.join(main, '.git', 'worktrees', 'broken', 'commondir'),
        ).writeAsStringSync('\n');
        expect(decisionOriginRegister(register), 'broken');
      });
    });
  });

  group('a linked worktree reads as its own repository', () {
    test('lint resolves a sibling edge naming the repo, not the worktree', () {
      final main = mainCheckout('alpha');
      final checkout = p.join(main, '.claude', 'worktrees', 'wt');
      final register = Directory(p.join(checkout, 'docs', 'decisions'))
        ..createSync(recursive: true);
      linkWorktree(checkout, main, id: 'wt');
      File(p.join(checkout, 'lib', 'fixture.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('final class Fixture {}\n');
      File(p.join(register.path, '2026-02-01-x.md')).writeAsStringSync('''
---
status: accepted
date: 2026-02-01
decision-makers: [fixture]
register:
  spec: 1
  slug: x
  surfaces: ["lib/**"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: [bravo#y]
  bead: null
  legacy-id: null
---

# x
''');
      final roster = _FakeRoster([
        DecisionRegisterSnapshot(
          originRegister: 'bravo',
          originPath: 'bravo/docs/decisions',
          entries: [
            DecisionEntry(
              file: 'bravo/docs/decisions/2026-02-01-y.md',
              body: '# y',
              status: 'accepted',
              date: '2026-02-01',
              spec: 1,
              slug: 'y',
              surfaces: const ['lib/**'],
              obsoletes: const [],
              updates: const ['alpha#x'],
              cachedObsoletedBy: null,
              cachedUpdatedBy: const [],
              bead: null,
              legacyId: null,
              decisionMakers: const ['fixture'],
            ),
          ],
        ),
      ]);

      final result = DecisionLintService(
        roster: roster,
      ).lint(registerPath: register.path, repoRoot: checkout);

      expect(result.isClean, isTrue, reason: '${result.toJson()}');
    });
  });
}
