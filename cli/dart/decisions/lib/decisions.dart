/// The decisions register engine — the deterministic half of the pattern.
///
/// A register is a directory of MADR-profile markdown files. This library
/// parses them into [DecisionEntry] values; the graph, lint and render layers
/// build on top. See `SPEC.md` at the repository root.
library;

export 'src/entry.dart';
export 'src/graph.dart';
export 'src/index.dart';
export 'src/index_command.dart';
export 'src/render.dart';
