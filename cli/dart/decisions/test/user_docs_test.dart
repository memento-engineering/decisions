import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The repository root, relative to the package root.
const _repoRoot = '../../..';

/// The user docs the tier-1 adopter reads: the README's verb inventory and
/// the two style guides, the starter in `templates/` and this register's own.
void main() {
  group('the README names every tier-1 verb', () {
    late String readme;
    late List<String> verbs;

    setUpAll(() {
      readme = File(p.join(_repoRoot, 'README.md')).readAsStringSync();
      verbs = DecisionsCommandRunner(
        output: StringBuffer(),
      ).commands.keys.where((verb) => verb != 'help').toList();
    });

    test('in the tier table', () {
      final row = readme
          .split('\n')
          .singleWhere((line) => line.startsWith('| 1 — CLI |'));
      for (final verb in verbs) {
        expect(row, matches(RegExp('[ `/]$verb[ `/]')), reason: verb);
      }
    });

    test('in the Status section', () {
      final status = readme.substring(readme.indexOf('\n## Status\n'));
      for (final verb in verbs) {
        expect(status, contains('`$verb`'), reason: verb);
      }
    });
  });

  for (final path in ['templates/STYLE.md', 'docs/decisions/STYLE.md']) {
    group(path, () {
      late File file;

      setUp(() => file = File(p.join(_repoRoot, path)));

      test('is a register document, never an entry', () {
        expect(file.existsSync(), isTrue);
        expect(isDecisionEntryFile(file.path), isFalse);
      });

      test('is prose, with no front matter for the CLI to parse', () {
        expect(file.readAsStringSync(), startsWith('# Style guide\n'));
        expect(
          () => parseEntry(file.path),
          throwsA(isA<DecisionParseException>()),
        );
      });
    });
  }

  test('the self-hosted register reads its STYLE.md as no entry', () {
    final register = p.join(_repoRoot, 'docs', 'decisions');
    final reported = <DecisionParseException>[];

    final entries = readRegister(register, onParseError: reported.add);

    final files = Directory(register).listSync().whereType<File>();
    expect(files.map((file) => p.basename(file.path)), contains('STYLE.md'));
    expect(reported, isEmpty);
    expect(
      entries,
      hasLength(files.where((file) => isDecisionEntryFile(file.path)).length),
    );
  });

  test('guide decide hands the self-hosted style guide to a writer', () async {
    final register = p.join(_repoRoot, 'docs', 'decisions');
    final style = p.join(register, 'STYLE.md');
    final output = StringBuffer();

    final code = await DecisionsCommandRunner(
      output: output,
    ).run(['guide', 'decide', '--register', register]);

    expect(code, 0);
    expect(output.toString(), contains('# Register style guide: $style\n'));
    expect(output.toString(), endsWith(File(style).readAsStringSync()));
  });
}
