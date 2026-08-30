---
status: accepted
date: 2026-08-30
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: legacy-register-migration
  surfaces:
    - "*/docs/adr/**"
    - "*/docs/adrs/**"
    - "*/docs/decisions/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# Legacy registers convert mechanically with empty edges; the graph is built at dockets

## Context and Problem Statement

Six repos hold `docs/adr/ADR-0000` registers — the_grid (59 amendments), genesis (47),
genesis-grid (39), power_station (32), expression (9), lenny (3) — ~189 entries and ~595 KB, plus
33 ratified `ADR-000N` documents. All of it is cited by number across bead text, PR bodies, other
ADRs, and the `adr-alignment` rubric. Nothing can be lost and no existing citation may break.

The hard part is that the supersession graph is narrated in **title prose**: `power_station` A25
reads "RETIRING pending A5 and pending A7(3), RE-HOMING pending A10's proof point." No parser
recovers that correctly.

## Considered Options

* **A — big-bang parse and convert**, inferring edges from the prose
* **B — freeze legacy in place, start fresh** at `docs/decisions/`
* **C — mechanical convert with empty edges**, curated at dockets

## Decision Outcome

**Option C.** A script emits one file per amendment: **body verbatim**, `spec: 1`,
`status: accepted`, `decision-makers: [agent]`, `register.legacy-id: A47`, and **all edges left
empty rather than guessed**.

* Nothing is lost, because the body is copied verbatim.
* Nothing is fabricated, because edges are blank rather than inferred. A wrong graph is worse than
  no graph — it would make the committee lens confidently cite relations that do not exist.
* The graph is built incrementally on the entries a docket actually touches, which is the same
  spend-attention-where-it-earns-it principle behind trigger-based codification.

**Citations are preserved by `register.legacy-id`.** `A47` resolves; tooling accepts both forms.
New entries in a converted register use slugs per
[entry-identity](2026-08-30-entry-identity.md), so converted registers are mixed.

**The 33 ratified `ADR-000N` documents convert too**, with the human in `decision-makers`. If they
did not, views could not be regenerated — a renderer cannot produce a document from a graph that
does not contain it — and we would be left with the two-surface problem this pattern exists to
kill. the_grid's `ADR-0001-technical-foundations` carries ten numbered clauses and is really ten
decisions; splitting that is judgement, not script, so it converts whole-doc as one entry and gets
split at a docket.

* **A rejected** because inferred edges would be confidently wrong.
* **B rejected** because a permanent second surface is precisely the `pow-lq6` bug class.

### Consequences

* Good, because the conversion script needs no cleverness and no NLP.
* Good, because one surface from day one; the lens stops being repo-local by construction.
* Bad, because converted registers are edge-poor for a long time — the graph's value accrues
  slowly rather than arriving with the migration.
* Bad, because 189 entries land in one commit per repo with no human having re-read them. They were
  already binding, so this changes their location and not their force.

### Confirmation

Post-conversion: every `A<n>` cited anywhere in the org resolves via `legacy-id`; entry count
matches amendment count per repo; `decisions lint` passes on all six registers.
