---
status: accepted
date: 2026-09-13
decision-makers:
  - governor
consulted:
  - nico
informed: []
register:
  spec: 1
  slug: successor-updated-by-dirt-does-not-block-force-mutation
  surfaces:
    - "cli/dart/decisions/lib/src/mutation.dart"
  obsoletes: []
  updates:
    - force-mutations-scope-cleanliness-to-touched-entries
  obsoleted-by: null
  updated-by: []
  bead: dec-o67
  legacy-id: null
---

# Successor updated-by dirt does not block force mutation

## Context and Problem Statement

The touched-entry cleanliness rule deadlocked a measured 37-operation docket. Its first update
could clean the target cache, but the successor was itself a later backlog target with an
unwritten `force.updated-by` cache. Every operation in a chained backlog therefore refused on its
successor before any target cache could be settled, even though each successor diagnostic would
be resolved by a later authored operation in the same docket.

The force mutation must preserve its integrity boundary: every diagnostic on the target and every
other diagnostic on the successor must still refuse atomically. Standalone lint must also keep
reporting the complete register without adopting a mutation-only exemption.

## Considered Options

* Exempt the successor's pending `force.updated-by` diagnostic in the existing touched-entry
  candidate check.
* Add batch mutation or topological docket ordering so successors settle before they are cited.

## Decision Outcome

force.updated-by is exempt only when the diagnostic belongs to the successor entry. The existing
single complete candidate lint still refuses every diagnostic on the target and every other rule
on the successor. It still groups retained diagnostics deterministically, reports their original
repository-relative paths, and writes only the target atomically.

This exemption allows a sequence of authored force operations to settle chained backlogs in docket
order because the skipped cache is one that a later operation will derive. It does not change
`DecisionLintService.lint`; standalone lint continues to report an unwritten successor cache until
that later operation settles it.

Batch mutation and topological docket ordering are rejected because they would change both the
force verb contract and the docket workflow to obtain the same final caches.

### Consequences

* Good, because a fully authored chained backlog can settle without hand edits or a privileged
  ordering mechanism.
* Good, because target dirt and non-`force.updated-by` successor dirt continue to refuse without
  writes.
* Bad, because a successful force operation can temporarily leave its successor's pending cache
  visible to standalone lint until the docket reaches that successor.
