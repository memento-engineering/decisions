---
status: accepted
date: 2026-09-13
decision-makers:
  - governor
consulted:
  - refiner
  - spec-readiness
informed: []
register:
  spec: 1
  slug: force-mutations-scope-cleanliness-to-touched-entries
  surfaces:
    - "cli/dart/decisions/lib/src/mutation.dart"
  obsoletes: []
  updates:
    - the-decision-register
  obsoleted-by: null
  updated-by:
    - successor-updated-by-dirt-does-not-block-force-mutation
  bead: dec-3g7
  legacy-id: null
---

# Force mutations scope cleanliness to touched entries

## Context and Problem Statement

A force mutation writes one target's derived cache only after linting a complete candidate
register. The original precondition refused that write for any non-exempt diagnostic anywhere in
the register. On 2026-09-13, a register with more than 25 pre-existing `force.updated-by`
diagnostics refused two otherwise valid amendments because of unrelated `force.updated-by` and
`surface.unmatched` findings. Both authored amendments landed, but their target caches could not
be written, so the guard added two more diagnostics to the backlog that caused the refusal.

The operation still needs to fail closed when its own inputs cannot produce a clean target and
successor. It does not gain integrity by coupling their cache write to unrelated entries, and the
standalone lint verdict must continue to report the complete register without exemptions added by
the mutation policy.

## Considered Options

* Scope the precondition to the target and successor touched by the force operation.
* Keep the whole-register precondition and add an actor-attributed override.
* Keep the whole-register precondition and require the existing backlog to be settled first.

## Decision Outcome

Each force command lints the complete candidate register once, but only non-exempt diagnostics on
its target or successor may refuse the write. A refusal identifies every dirty touched entry by
its original repository-relative path and its sorted rule ids. When neither touched entry is
dirty, the command writes only the target's derived cache; it never changes the successor or an
unrelated entry.

The actor-attributed override is rejected because it preserves a whole-register coupling with no
integrity payoff and adds a second route around the invariant. Settling the backlog first is
rejected because the global refusal makes each correct new amendment join that backlog, making
the precondition progressively less satisfiable.

`DecisionLintService.lint` remains unchanged: unrelated diagnostics continue to make standalone
lint unclean before and after a force mutation. Only the mutation service's refusal scope changes.

### Consequences

* Good, because correct amendments can settle their own caches without being blocked by unrelated
  register drift.
* Good, because dirty touched entries still refuse atomically with path-bearing diagnostics.
* Bad, because a force command can succeed while standalone lint still reports unrelated register
  problems that operators must settle separately.
