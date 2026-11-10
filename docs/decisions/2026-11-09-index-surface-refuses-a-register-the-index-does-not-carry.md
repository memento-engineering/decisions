---
status: accepted
date: 2026-11-09
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "index-surface-refuses-a-register-the-index-does-not-carry"
  surfaces:
    - "cli/dart/decisions/lib/src/index_command.dart"
    - "cli/dart/decisions/lib/src/register_union.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-534"
  legacy-id: null
---

# decisions index refuses a surface under a register it does not carry

## Context and Problem Statement

`decisions index --surface` takes a roster-qualified path, `register/path`, and returned an empty
answer for any spelling it did not recognise. Measured at the lunar grid home on 2026-09-09, a
qualified path into the station's register returned five decisions; the same path without its
register prefix, which is what a person reads off a file tree, returned none; and a nonexistent
path under a known register also returned none. The last two answers were identical, and both
read as "this surface is ungoverned".

This is the failure class of dec-5l8, where a worktree naming defect made the same query silently
empty inside a lane and took a hard-blocked review round to notice, because empty is a plausible
answer. That defect is fixed; the silence was not.

## Decision Outcome

**A governed-surface query whose register the index did not read is a usage error, not an empty
answer; a query under a register it did read keeps answering, empty included.**

1. **Empty means ungoverned only for a register the index read.** Only there has every entry that
   could govern the path been seen, so only there is an empty answer true.
2. **The refusal names the registers that were read.** A caller corrects a misspelt or missing
   register from the message itself, without a second command.
3. **A query's register is its first path segment, read in one shared place.** The path is
   normalised exactly as surface matching normalises it before the segment is taken, so the check
   and the match cannot disagree. A query names a concrete path, so a wildcard or empty first
   segment names no register and is refused.
4. **An unqualified path is not guessed, even with one register indexed.** The same argument
   must not change meaning as the roster grows.
5. **Search is not changed here.** When `decisions search` adopts this rule it reuses the same
   shared reading of a query's register, as `lexical-precedent-search` requires.

The refusal is a usage error, so it follows
`every-verb-prints-refusals-and-errors-on-stderr-and-results-on-stdout`: the message and usage go
to standard error with exit `64`, and nothing reaches standard output. The union the index reads
is built as before, each register under the slug limit its caller supplies, as
`a-registers-slug-limit-is-a-caller-setting-80-by-default` requires. This does not amend
`cross-register-force-edges`: that entry rules on edges a checkout cannot see, and declining to
answer for an unread register is the query-side form of its unresolvable-not-wrong ruling.

This is wrong if a caller comes to need a silent empty answer for a register outside the roster
it indexed; that takes a new entry.

## Considered Options

* Accept an unqualified path when exactly one register is indexed.

Accepting it is rejected by ruling 4: a query that works against one register would start to fail,
or to mean something else, the day a second register joins the roster.

### Consequences

* Good, because a mistyped register is told apart from a path no decision governs.
* Good, because the error lists the registers a caller can choose from.
* Bad, because a committee lookup on a repository whose register the roster does not carry now
  exits `64` where it returned an empty array, and the decision-alignment rubric reports that as a
  failed lookup rather than a clean one.
