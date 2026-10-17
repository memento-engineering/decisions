import 'dart:io';

import 'package:decisions/decisions.dart';

/// The standalone `decisions` executable.
///
/// Exit codes: 0 success; 1 lint findings or a refused mutation; 64 a
/// malformed invocation.
Future<void> main(List<String> args) async {
  exitCode = await DecisionsCommandRunner().run(args);
}
