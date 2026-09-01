import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:decisions_grid_assets/decisions_grid_assets.dart';
import 'package:test/test.dart';

const String _sourceRoot =
    '../../cli/dart/decisions/test/fixtures/index_registers/source_repo';
const String _otherRoot =
    '../../cli/dart/decisions/test/fixtures/index_registers/other_repo';

final class FakeResidentStationContext {
  FakeResidentStationContext(this.roots);

  List<String> roots;
  int reads = 0;

  Iterable<String> mountedSubstationRoots() {
    reads++;
    return List<String>.unmodifiable(roots);
  }
}

void main() {
  test('station composition exposes lint and runtime roster index', () async {
    final resident = FakeResidentStationContext(['ignored-at-construction']);
    final output = StringBuffer();
    final command = buildDecisionsCommand(
      mountedSubstationRoots: resident.mountedSubstationRoots,
      output: output,
    );
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(command);

    expect(resident.reads, 0);
    expect(runner.commands['decisions'], same(command));
    expect(command.subcommands.keys, containsAll(['lint', 'index']));

    resident.roots = [_sourceRoot, _otherRoot, 'missing-substation'];
    expect(await runner.run(['decisions', 'index']), 0);
    expect(resident.reads, 1);

    final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
    final decisions = (decoded['decisions'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(decisions, hasLength(2));
    expect(
      decisions.map((decision) => decision['originRegister']),
      unorderedEquals(['source_repo', 'other_repo']),
    );
  });

  test('empty resident roster is refused loudly', () async {
    final runner = CommandRunner<int>('station', 'fixture')
      ..addCommand(
        buildDecisionsCommand(
          mountedSubstationRoots: () => const ['missing-substation'],
          registerExists: (_) => false,
          output: StringBuffer(),
        ),
      );

    await expectLater(
      runner.run(['decisions', 'index']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
  });

  test('declares spec-1 read range and no writes', () {
    expect(decisionsGridAssetsReadSpecMinimum, 1);
    expect(decisionsGridAssetsReadSpecMaximum, 1);
    expect(decisionsGridAssetsWrittenDecisionSpecs, isEmpty);
  });
}
