---
status: accepted
date: 2026-08-30
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: spec-and-artifact-versioning
  surfaces:
    - "SPEC.md"
    - "schema/**"
    - "cli/**"
    - "grid_assets/**"
  obsoletes: []
  updates: [the-decision-register]
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# The spec is an integer declared per entry; artifacts are semver; registers are not versioned

## Context and Problem Statement

Once more than one repo writes entries and more than one tool reads them, the format needs a
version — and so does every consumer that claims to understand it. Three different things could
carry a version (the format, the shipped artifacts, the register itself) and they move at
completely different rates. Getting this wrong means either a spec bump that rewrites 189
historical entries, or tools that silently mis-read files they were never built for.

## Decision Outcome

**The spec is an integer**, `register.spec: 1`. Formats have no patch releases; even a purely
additive change breaks a strict validator, so the only question a reader ever asks is which version
this is. Semver would imply a compatibility gradient that does not exist.

**Declared per entry, not per register.** The register is append-only: 2026 entries stay in the
2026 format forever, mixed-version registers are normal and permanent rather than a migration debt,
and a file must be self-describing to a grepper with no tooling.

**Artifacts are semver**, tagged `<name>-v<version>` per the house convention. `cli/dart/decisions`
and `grid_assets/decisions_grid_assets` version independently, and each declares which spec
versions it reads and which it writes.

**Registers carry no version.** A register is a directory.

**Compatibility rule: readers support every spec version ≤ their own; writers emit only their own.**
A breaking spec bump ships its migration tool in the same release.

### Consequences

* Good, because a spec bump never rewrites history. Combined with the immutable-body rule from
  [madr-profile](2026-08-30-madr-profile.md), migration is permanently bounded to the cached force
  block.
* Good, because a tool can refuse a file it does not understand instead of mis-parsing it.
* Bad, because every entry carries a `spec:` line forever. One line, in exchange for
  self-description.
* Neutral, because independent artifact versions mean the CLI and the grid pack can drift; each
  declaring its spec range is what keeps that legible.
