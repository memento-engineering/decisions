---
status: accepted
date: 2026-10-24
decision-makers:
  - nico
  - agent
consulted: []
informed: []
register:
  spec: 1
  slug: a-registers-style-md-is-its-style-guide-and-uppercase-files-are-not-entries
  surfaces:
    - "SPEC.md"
    - "docs/decisions/*.md"
    - "cli/dart/decisions/lib/src/entry.dart"
    - "cli/dart/decisions/lib/src/lint.dart"
    - "cli/dart/decisions/lib/src/mutation.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: dec-vqt
  legacy-id: null
---

# A register's STYLE.md is its style guide, and uppercase files are not entries

## Context and Problem Statement

A register fixes the shape of an entry — front matter, force, edges — and says nothing about its
prose. Each register still has a voice worth keeping: how titles are phrased, what a Context
section leads with, which conventions its sections follow. Today that lives in agent memory or a
repo's `CLAUDE.md`, where it is pushed into every session whether or not that session writes a
decision, and where it is not next to the register it describes.
`memento-engineering#knowledge-lives-in-the-smallest-surface-that-can-enforce-it` puts it in the
smallest surface that holds it, which is the register directory itself, and
`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help` says a writer pulls
that guidance when it is about to write, rather than being handed it at session start.

The register directory could not hold such a file. Every walk — `readRegister`, `decisions lint`
and the force mutations' candidate copy — took every `*.md` file as an entry, each with its own ad
hoc filter. A `README.md` or `STYLE.md` beside the entries failed to parse: lint reported it as a
malformed entry, and readers that do not tolerate parse errors refused the whole register.

## Decision Outcome

**A file in a register directory whose name is all uppercase — `^[A-Z][A-Z0-9_-]*\.md$`, such as
`README.md` or `STYLE.md` — is a register document, never an entry.** Every other `*.md` file is an
entry, and a malformed one is still reported. No valid entry is excluded: an entry's filename is
`YYYY-MM-DD-<slug>.md`, so it starts with a digit.

**`STYLE.md` is the register's style guide**: optional, free-form prose that a writer reads before
writing an entry body — voice, title shape, section conventions. It governs the authored body only
and cannot override anything `SPEC.md` fixes.

**One style guide per register, and no inheritance across the roster** (nico's ruling,
2026-10-24). An org register's `STYLE.md` says nothing about a repo register's entries. A register
that wants another's voice copies its guide.

In the engine, one exported predicate, `isDecisionEntryFile`, replaces the three separate filters
in `readRegister`, `DecisionLintService` and the force mutations, so the rule cannot drift between
them. `SPEC.md` states the rule under *Location and identity*.

**The spec stays at 1.** Under
[spec-and-artifact-versioning](2026-08-30-spec-and-artifact-versioning.md) the spec integer is
declared per entry and versions the entry format, and a register carries no version. This rule
changes no entry: every spec-1 entry reads exactly as it did. It changes which files in the
directory are entries, and a register document has no front matter in which to declare a spec. The
break it does cause, an older reader rejecting `STYLE.md`, falls on the artifacts, so it is carried
by the `decisions` release that ships the predicate.

### Consequences

* Good, because a register carries its own README and style guide, in the directory a writer is
  already working in, at no cost to sessions that never write a decision.
* Good, because the three walks that decide what an entry is now share one predicate.
* Bad, because `decisions` 0.3.0 and earlier read `STYLE.md` or `README.md` as a malformed entry:
  lint fails and the force mutations refuse. A register that adopts a style guide needs the next
  release in every place it is linted, CI included.
* Bad, because an uppercase file meant as an entry, such as a legacy `ADR-0001.md`, is now skipped
  silently rather than reported. A migrated register must be converted, not left in place.
* Bad, because without inheritance, an org that wants one voice keeps copies of one guide in sync
  by hand.
