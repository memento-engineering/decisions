---
status: accepted
date: 2026-11-07
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "decisions-resurface-re-points-a-surface-after-a-move-and-records-no-entry"
  surfaces:
    - "SPEC.md"
    - "README.md"
    - "cli/dart/decisions/lib/src/mutation.dart"
    - "cli/dart/decisions/lib/src/command.dart"
    - "skills/ratify/SKILL.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-ca3"
  legacy-id: null
---

# decisions resurface re-points a surface after a move, and records no entry

## Context and Problem Statement

A restructure (a move, a rename, a fold or a split) leaves entries naming globs that still
resolve, but to the wrong files, or that resolve to nothing. Every reader of `surfaces` then
answers wrongly: which entries govern a path, which entries `decisions new` shows as covering
a surface, and which open work a vacate flags (memento-engineering/decisions issue 67).
`SPEC.md`'s Edges table listed `surfaces` as authored and written by the author once, so the
only ways to re-point one were a hand edit of an entry, or a superseding entry for each
affected decision, which records a move as if it were a ruling.

On 2026-11-06 nico ruled the shape: a rewrite verb, not a record in the register.

## Considered Options

* A superseding entry for each affected decision
* A move record in the register that readers apply to the surfaces they read
* A verb that rewrites the surfaces in place

## Decision Outcome

**After its author, only `decisions resurface` writes an entry's `surfaces`: it re-points a
glob in place, records no entry and changes no force.**

1. **A move decides nothing.** When the files an entry names move, what it governs is
   unchanged; only their address is. A re-point therefore adds no entry and no record file,
   and the commit that moves the files carries the rewrite (nico, 2026-11-06). A superseding
   entry per decision is rejected because it fills the register with entries that rule
   nothing. A move record is rejected because every reader would have to apply it, so a
   register read by grep would still answer with the old paths.
2. **It rewrites one glob and nothing else.** A surface equal to the old glob becomes the new
   one; the body, the other authored fields and the force cache keep every byte. An entry
   that already names the new glob keeps it once, so a fold leaves no duplicate.
3. **It is not a docket act.** A re-point changes no force, so it needs no successor and no
   human ruling. A docket still never edits an authored field.
4. **All or nothing, and never dirtier.** It writes nothing when an entry it was asked to
   rewrite does not carry the old glob, when the new glob matches nothing in this checkout,
   or when the rewrite would give a rewritten entry a lint finding it did not already carry.
   A roster-wide new glob is exempt from the checkout check, the one class
   `decisions-lint-gate-is-the-vended-register-ci-check` already exempts. A finding the entry
   already carried does not block a re-point, as
   `force-mutations-scope-cleanliness-to-touched-entries` rules for force changes.
5. **Force does not limit it.** It rewrites a superseded or vacated entry as readily as an
   accepted one: those entries name the same moved files, and their surfaces still answer
   which decisions once governed a path.

`DecisionResurfaceService` in `cli/dart/decisions/lib/src/mutation.dart` carries the rule,
and `SPEC.md` states it in its Edges section. No accepted entry rules who writes `surfaces`,
so this entry amends none and carries no `updates` edge. Entries stay at
`register.spec: 1`, as `spec-and-artifact-versioning` requires: a re-pointed entry has the
same fields in the same shape.

This ruling is wrong if a re-point ever needs a judgement about what an entry governs rather
than where its files live. A split that divides one decision's reach between two places is
such a judgement, and it takes a new entry. It is also wrong if a reader needs a surface's
former paths from the register itself rather than from version control.

### Consequences

* Good, because a restructure re-points every affected entry with one command, in the
  commit that moves the files.
* Good, because the register stays a record of rulings: no entry exists only to say a
  directory moved.
* Bad, because an entry's surfaces can now differ from what its author wrote, and the record
  of that change lives in version control, not in the register.
