/// The agent instructions compiled into the `decisions` binary.
///
/// Each [Guide] is one canonical skill from the repository's `skills/`
/// directory, rendered into `guides.g.dart` by `tool/generate_guides.dart`.
/// Shipping them inside the binary means an adopter's agent reads the
/// instructions that match the installed engine, never a stale copy.
library;

part 'guides.g.dart';

/// One canonical skill, carried by the binary.
final class Guide {
  /// Creates a guide from a skill's front matter and body.
  const Guide({
    required this.name,
    required this.description,
    required this.body,
  });

  /// The skill name, which is also the `decisions guide` topic.
  final String name;

  /// The skill's one-paragraph description, from its front matter.
  final String description;

  /// The skill's markdown body, after the front matter.
  final String body;
}

/// Every guide this binary carries, sorted by [Guide.name].
const List<Guide> bundledGuides = _bundledGuides;
