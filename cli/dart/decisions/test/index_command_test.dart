import 'dart:convert';

import 'package:args/command_runner.dart';
import 'package:decisions/decisions.dart';
import 'package:test/test.dart';

const _sourceRegister =
    'test/fixtures/index_registers/source_repo/docs/decisions';
const _otherRegister =
    'test/fixtures/index_registers/other_repo/docs/decisions';

void main() {
  test(
    'accepts explicit register paths and emits JSON without a station',
    () async {
      final output = StringBuffer();
      final runner = CommandRunner<int>('decisions', 'Decision register tools')
        ..addCommand(IndexCommand(output: output));

      final exitCode = await runner.run([
        'index',
        _sourceRegister,
        _otherRegister,
      ]);
      final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
      final decisions = (decoded['decisions'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      expect(exitCode, 0);
      expect(decoded['spec'], 1);
      expect(decisions, hasLength(2));
      expect(
        decisions.map((decision) => decision['originRegister']),
        containsAll(['source_repo', 'other_repo']),
      );
    },
  );

  test('requires at least one explicit register path', () async {
    final runner = CommandRunner<int>('decisions', 'Decision register tools')
      ..addCommand(IndexCommand(output: StringBuffer()));

    await expectLater(
      runner.run(['index']),
      throwsA(
        isA<UsageException>().having(
          (error) => error.message,
          'message',
          contains('at least one register directory is required'),
        ),
      ),
    );
  });

  test('uses injected register paths lazily when no explicit paths', () async {
    var resolved = const <String>[];
    var calls = 0;
    final output = StringBuffer();
    final runner = CommandRunner<int>('decisions', 'Decision register tools')
      ..addCommand(
        IndexCommand(
          output: output,
          registerPaths: () {
            calls++;
            return resolved;
          },
        ),
      );

    expect(calls, 0);
    resolved = [_sourceRegister, _otherRegister];

    expect(await runner.run(['index']), 0);
    expect(calls, 1);
    final decoded = jsonDecode(output.toString()) as Map<String, dynamic>;
    expect(decoded['decisions'], hasLength(2));
  });
}
