import 'dart:io';

import 'package:decisions/decisions.dart';
import 'package:test/test.dart';

import '../tool/generate_guides.dart';

void main() {
  test('guides.g.dart is current (run tool/generate_guides.dart)', () {
    expect(
      File(guidesFile).readAsStringSync(),
      renderGuides(readSkills(skillsDirectory)),
    );
  });

  test('every canonical skill ships as a guide', () {
    expect(
      bundledGuides.map((guide) => guide.name),
      orderedEquals(readSkills(skillsDirectory).keys.toList()..sort()),
    );
    for (final guide in bundledGuides) {
      expect(guide.description, isNotEmpty);
      expect(guide.body, startsWith('# '));
    }
  });

  group('renderGuides', () {
    String skill(String name, String body) =>
        '---\nname: $name\ndescription: Use it when it fits.\n---\n\n$body';

    test('sorts guides by name and keeps bodies verbatim', () {
      final rendered = renderGuides({
        'zeta-skill': skill('zeta-skill', r'# Zeta \ $x'),
        'alpha': skill('alpha', '# Alpha\n'),
      });

      expect(
        rendered.indexOf("name: 'alpha'"),
        lessThan(rendered.indexOf("name: 'zeta-skill'")),
      );
      expect(
        rendered,
        contains("const _zetaSkillBody = r'''\n# Zeta \\ \$x\n'''"),
      );
      expect(rendered, contains("description: 'Use it when it fits.',"));
    });

    test('escapes a description for a single-quoted literal', () {
      final rendered = renderGuides({
        'a': "---\nname: a\ndescription: \"it's \$5\"\n---\n\n# A\n",
      });

      expect(rendered, contains(r"description: 'it\'s \$5',"));
    });

    test('refuses a skill whose name disagrees with its directory', () {
      expect(
        () => renderGuides({'decide': skill('other', '# Other\n')}),
        throwsFormatException,
      );
    });

    test('refuses a skill with no front matter', () {
      expect(() => renderGuides({'a': '# A\n'}), throwsFormatException);
    });

    test('refuses a body that would end the raw string', () {
      expect(
        () => renderGuides({'a': skill('a', "# A\n'''\n")}),
        throwsFormatException,
      );
    });
  });
}
