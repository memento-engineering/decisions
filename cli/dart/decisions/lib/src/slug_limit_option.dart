import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'entry.dart';
import 'register_union.dart';

/// The option every verb that reads a register takes.
const _maxSlugLength = 'max-slug-length';

/// Adds `--max-slug-length` to [parser].
void addMaxSlugLengthOption(ArgParser parser) {
  parser.addOption(
    _maxSlugLength,
    valueHelp: 'n',
    help:
        'Slug limit for every register this run reads; overrides the '
        'composed limit (default $defaultMaxSlugLength).',
  );
}

/// The slug limits [command]'s run applies: one uniform limit when
/// `--max-slug-length` is given, and otherwise [composed].
///
/// A value that is not a positive integer is a usage error.
DecisionSlugLimits resolveSlugLimits(
  Command<int> command,
  DecisionSlugLimits composed,
) {
  final raw = command.argResults!.option(_maxSlugLength);
  if (raw == null) return composed;
  final value = int.tryParse(raw.trim());
  if (value == null || value <= 0) {
    command.usageException(
      '--$_maxSlugLength must be a positive integer, got "$raw".',
    );
  }
  return DecisionSlugLimits.uniform(value);
}
