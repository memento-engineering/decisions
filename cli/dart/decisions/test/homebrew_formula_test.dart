import 'package:test/test.dart';

import '../tool/homebrew_formula.dart';

void main() {
  String sums(String version, Iterable<String> targets) => [
    for (final (index, target) in targets.indexed)
      '${'$index' * 64}  decisions-$version-$target',
  ].join('\n');

  test('pins every target asset to its checksum', () {
    final formula = renderFormula(
      version: '0.3.0',
      sha256sums: sums('0.3.0', releaseTargets),
    );

    expect(formula, contains('version "0.3.0"'));
    for (final (index, target) in releaseTargets.indexed) {
      expect(
        formula,
        matches(RegExp('-$target"\\n\\s+sha256 "${'$index' * 64}"')),
      );
    }
  });

  test('accepts binary-mode checksum lines', () {
    final formula = renderFormula(
      version: '0.3.0',
      sha256sums: sums('0.3.0', releaseTargets).replaceAll('  ', ' *'),
    );

    expect(formula, contains('sha256 "${'0' * 64}"'));
  });

  test('refuses a release missing a target', () {
    expect(
      () => renderFormula(
        version: '0.3.0',
        sha256sums: sums('0.3.0', releaseTargets.take(2)),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('decisions-0.3.0-linux-arm64'),
        ),
      ),
    );
  });
}
