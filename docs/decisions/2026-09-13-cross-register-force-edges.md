---
status: accepted
date: 2026-09-13
decision-makers:
  - governor
consulted: []
informed: []
register:
  spec: 1
  slug: cross-register-force-edges
  surfaces:
    - "SPEC.md"
    - "schema/**"
    - "cli/dart/decisions/lib/**"
  obsoletes: []
  updates:
    - madr-profile
  obsoleted-by: null
  updated-by: []
  bead: dec-b17
  legacy-id: null
---

# Force edges cross registers, and an absent register is unresolvable rather than wrong

## Context and Problem Statement

The format has spelled a cross-register citation `<repo>#<slug>` since spec 1, and the entry
schema already admits one wherever a reference is allowed. The graph stopped at the directory
boundary anyway, because every force verb read exactly one register directory.

Two measured cases, both from the 2026-09-13 manual docket. `power_station` adr-0004 caches an
`updated-by` naming two org-register entries; those edges are real, but lint derived its
expectation from one directory, found neither source, and reported `force.updated-by` on a
correct entry. `decisions update` could not re-settle it, because the successor is not in the
directory it reads. Separately, `the_grid` adr-0008 Decision 10 is superseded by `power_station`'s
agent-environment layer, and no verb could record that edge at all: an `obsoletes` edge across
registers was unrepresentable except by the hand edit the cached-block rule forbids.

Both failures are the same missing input. The verbs had no roster.

## Considered Options

* Resolve cross-register references through a roster the verb is given, and exempt what the roster
  cannot see.
* Keep one register per verb and let a cross-register edge live only in prose.
* Require every cross-register decision to move into the org register, so all edges are local.

## Decision Outcome

`obsolete`, `update` and `vacate` accept a `<repo>#<slug>` successor, and `lint` resolves cached
and authored qualified references, both through a **roster**: the sibling registers this checkout
can see. The roster comes from repeatable `--roster` options, and otherwise from the register
resolver the caller already composed — the live mounted roster at tier 2.

A register the roster does not carry is **unresolvable, not wrong**. Its cached value is carried
through as satisfied and no diagnostic is raised, because a single checkout legitimately sees one
side of a graph that spans several — the same reasoning that already exempts a roster-wide
`surfaces` glob. A register the roster *does* carry is checked strictly: a qualified reference
that names no entry there is reported, and a cache that disagrees with the roster's authored
edges is a mismatch naming what was expected.

One derivation produces both what lint checks and what a mutation writes, so the two can never
disagree. A force mutation still lints a complete candidate register before writing, and the
candidate keeps the target register's own `<repo>/docs/decisions` shape so it is checked under the
same origin register, and therefore against the same cross-register edges, as the register it will
replace.

Prose-only edges are rejected because the register's whole claim is that force is mechanical.
Moving every cross-register decision into the org register is rejected because it inverts
`memento-engineering#org-decisions-live-in-the-org-register`: a decision belongs where it is
governed, and the org register is for decisions that govern more than one repo — not a dumping
ground for anything that happens to cite across a boundary.

### Consequences

* Good, because a correct cross-register cache lints clean in a single checkout, and the same
  cache is checked strictly wherever the roster is complete.
* Good, because the graph now spans the registers the org actually keeps, with no new vocabulary:
  the `<repo>#<slug>` handle the format already had is the whole interface.
* Bad, because force derived from a roster is only as complete as the roster. `DecisionGraph`
  itself remains single-register, so `isBinding` still answers from local edges alone; an entry
  obsoleted only from another register reads as binding to a roster-free consumer until the graph
  itself takes a roster.
