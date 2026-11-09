---
status: accepted
date: 2026-11-09
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "a-surface-must-resolve-only-on-an-entry-in-force"
  surfaces:
    - "cli/dart/decisions/lib/src/lint.dart"
    - "SPEC.md"
  obsoletes: []
  updates:
    - "decisions-lint-gate-is-the-vended-register-ci-check"
  obsoleted-by: null
  updated-by: []
  bead: "dec-4lp"
  legacy-id: null
---

# A surface must resolve only on an entry in force

## Context and Problem Statement

`decisions lint` reported an unmatched surface on every entry, whatever its force. Surfaces are
written once, so when a successor removed the files a superseded entry governed, the register's
lint failed until something matched the old glob again, and repositories kept stub directories
that existed only for the linter (memento-engineering/decisions issue 65). `decisions resurface`
re-points a surface whose files moved, but a removal leaves no new place to point at.

On 2026-11-06 nico ruled that the rule applies only to an entry in force.

## Decision Outcome

**A surface must resolve only on an entry in force. An entry superseded by another, vacated or
rejected may name surfaces that match nothing.**

1. **Force decides whether a surface is checked.** An entry superseded, vacated or rejected no
   longer governs, so a surface on it that matches nothing is history, not drift. An entry another
   entry only updates stays in force, and its surfaces must still resolve. Force is read from the
   entry's status line, so a grep of the register gives the linter's answer.
2. **A removal obsoletes; a move re-points.** A successor that removes a surface an earlier entry
   governs obsoletes that entry rather than updating it. Files that moved are still re-pointed with
   `decisions resurface`, which
   `decisions-resurface-re-points-a-surface-after-a-move-and-records-no-entry` makes the one
   exception to write-once surfaces, and this entry adds no other. Editing an old entry's surfaces
   to make lint pass is rejected, because the change is in what lint requires, not in old entries.
3. **One rule for every reader of lint.** Plain lint, the gate, the force verbs' candidate lint
   and the write path's candidate lint apply the same in-force test, held in one place. Plain lint
   keeps its default mode, output and exit codes; what changes is the rule set it applies. The
   gate's one exempt class, an unmatched roster-wide surface, is neither widened nor narrowed,
   because an out-of-force entry's surfaces are not exempted but not checked.

This updates `decisions-lint-gate-is-the-vended-register-ci-check`, points 1 and 2: plain lint and
the gate both stop reporting an unmatched surface on an entry out of force. That entry stays in
force with its other rulings intact, and since no surface it governs is removed, it is updated
rather than obsoleted, by this entry's own rule. This does not amend
`force-mutations-scope-cleanliness-to-touched-entries`, whose refusal stays scoped to target and
successor with no exemption of the mutation's own: a force verb that takes its target out of force
stops finding that target's surfaces unmatched only because lint stops checking them, for every
caller alike. It leaves `decisions-resurface-re-points-a-surface-after-a-move-and-records-no-entry`
untouched. Entries stay at `register.spec: 1`, as `spec-and-artifact-versioning` requires, because
the entry format is unchanged and every register that lints clean today still does.

This is wrong if a reader of the register comes to need an out-of-force entry's surfaces to
resolve in the checkout, or if successors routinely remove part of what an earlier entry governs
while that entry must stay in force. Either takes a new entry.

### Consequences

* Good, because removing the files a superseded decision governed needs no stub directory.
* Good, because a docket can obsolete or vacate an entry whose files are already gone.
* Bad, because an out-of-force entry's surfaces may name paths that no longer exist, and only
  version control shows what they held.
