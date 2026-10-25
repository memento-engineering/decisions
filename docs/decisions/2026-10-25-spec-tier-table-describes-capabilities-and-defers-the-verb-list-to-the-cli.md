---
status: accepted
date: 2026-10-25
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "spec-tier-table-describes-capabilities-and-defers-the-verb-list-to-the-cli"
  surfaces:
    - "SPEC.md"
    - "README.md"
    - "cli/dart/decisions/test/user_docs_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-9ed"
  legacy-id: null
---

# SPEC.md's tier table describes capabilities and defers the verb list to the CLI

## Context and Problem Statement

`SPEC.md`'s tier table listed the tier-1 CLI as `decisions index / search / lint / render / new /
obsolete / update / vacate`. The binary has never had a `render` verb: views are rendered by the
`renderViews` library function, which no command calls. The list also lacked five verbs the binary
does ship (`migrate-legacy`, `prime`, `guide`, `skills`, `doctor`), so a reader comparing it with
`README.md`'s tier table or `decisions --help` found three answers to one question.

The README's row was already right because `test/user_docs_test.dart` pins it to the command
runner in both directions. `SPEC.md`'s row had nothing pinning it, and it drifted the moment the
CLI grew a verb. `SPEC.md` is the normative text of the format, and the verb list is tooling: it
changes with every release while the format stays at spec 1. Keeping a release-shaped list in a
spec-shaped document puts it where no release is checked against it, against
`memento-engineering#knowledge-lives-in-the-smallest-surface-that-can-enforce-it`.

## Considered Options

* **Describe the capability** in `SPEC.md` and point at the README and `decisions --help` for the
  verbs.
* **Keep an exact list** in `SPEC.md` and pin it to the command runner with the test that already
  pins the README.

## Decision Outcome

**`SPEC.md`'s tier table describes what tier 1 can do, and leaves the list of verbs to the README
and `decisions --help`.** The tier-1 row now reads "a CLI that indexes, searches and lints the
register, records entries and writes force changes, JSON out", and a paragraph under the table
says that the README and `decisions --help` list the current verbs.

1. **Verbs `SPEC.md` defines stay where they are.** The sections on `decisions lint`, `index`,
   `search`, `new`, `obsolete`, `update` and `vacate` bind any tier-1 implementation, and nothing
   moves out of them. Only the inventory leaves.
2. **The README stays the inventory.** Its tier row and its Status section stay pinned to the
   command runner by `test/user_docs_test.dart`, as before.
3. **A test keeps `SPEC.md` from drifting back.** `test/user_docs_test.dart` now fails when the
   `SPEC.md` tier-1 row carries a code span, and when any `decisions <verb>` code span in `SPEC.md`
   names a verb the binary lacks.

An exact, pinned list in `SPEC.md` is rejected because it would make every new verb a change to the normative text with no change to the format,
and would demand a register entry for each one.

This changes no format rule. Entries stay at `register.spec: 1`, as
[spec-and-artifact-versioning](2026-08-30-spec-and-artifact-versioning.md) requires when the format
is unchanged. Item 6 of [the-decision-register](2026-08-29-the-decision-register.md) names the
tiers by capability already, so it is cited here and not amended.

### Consequences

* Good, because `SPEC.md` and the README can no longer disagree about the verbs: only one of them
  lists them, and a test checks that one against the binary.
* Good, because adding a verb no longer touches the normative text.
* Bad, because a reader of `SPEC.md` alone no longer sees the CLI's full surface and has to follow
  the link to the README or run `decisions --help`.
