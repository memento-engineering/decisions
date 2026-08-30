---
status: accepted
date: 2026-08-29
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: the-decision-register
  surfaces:
    - "SPEC.md"
    - "docs/decisions/**"
    - "engineering.memento/CLAUDE.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: [madr-profile, entry-identity, spec-and-artifact-versioning]
  bead: null
  legacy-id: null
---

# A decision register is a citation graph with force, recorded by anyone and ratified at a docket

## Context and Problem Statement

memento's six repos each keep a living `docs/adr/ADR-0000` AI-decision register — ~189 amendments,
~595 KB. The pattern works and its committee lens (`adr-alignment`) catches real contradictions,
but four properties broke down in practice, all traceable to one root: **the format sorts by
authorship and stores prose, where it should sort by force and store a graph.**

* **Promotion buys nothing, so it never happens.** The rubric already treats pending amendments as
  binding, making promotion documentation hygiene rather than authorization. `power_station`
  carries 16 pending and has promoted zero, ever; the org has recorded exactly one ratification
  round (genesis, 2026-06-13). A ceremony with no operational payoff loses to entropy.
* **The record is inverted.** ~6 KB essays for autonomous decisions; nothing durable for the
  human's rulings, which the old rule explicitly told agents *not* to write down. genesis is the
  only register annotating its decider — and the only one that ever ratified.
* **The format cannot express supersession.** `power_station` A25/A26/A27/A30 narrate retirement,
  re-homing and reversal in *title prose*. the_grid A53 is the failure case: a round wired work in
  direct contradiction of A52's recorded disposition and had to be hand-reverted.
* **Registers are repo-local; decisions are org-wide.** `pow-lq6` (P1): a space_station bead
  carried a file-watcher through a **grade-A** `adr-alignment` because the_grid's A50 lived in a
  register the lens structurally could not reach.

## Decision Outcome

1. **Every repo keeps a register at `docs/decisions/`** — one markdown file per decision, plain
   front matter, greppable with no tooling. Consolidated `ADR`-style documents become **rendered
   views** at `docs/decisions/views/`, generated from the graph.

2. **Authorship is a field, not a location.** Autonomous decisions and human rulings are recorded
   identically, distinguished by `decision-makers`. The prior rule sorted by authorship and
   prescribed silence for the highest-authority class in the org, which is why those rulings were
   lost to prose and reconstructed after the fact.

3. **A decision binds on write.** Force attaches when the entry is recorded, by anyone, in any
   session. There is no `pending` state. *(Ratified by Nico, 2026-08-29.)*

4. **The human gate is on force changes, not on recording.** Obsoleting, updating, vacating and
   rejecting happen at a **docket**, triggered by signal rather than calendar.

5. **Vacating requires a successor.** A withdrawn decision names its replacement or explicitly
   records that no rule governs the surface. Silence is not a valid outcome.

6. **The pattern ships as three tiers** — prose (nothing required), CLI (an ecosystem
   implementation), grid (a station-installed asset pack). The grid tier is the best-supported,
   never the only one.

### Consequences

* Good, because the highest-authority decisions in the org become durable for the first time.
* Good, because force changes — the only judgements that actually need a human — are the only
  thing a human is asked for.
* Bad, because a register with no proposal gate accumulates decisions no one reviewed until a
  docket fires. The lint and the docket triggers are what keep that from rotting.

## More Information

Prior art: Steve Yegge, *The Shape of Things to Come* — the layered `brain/` / `doc/` / beads /
`bd remember` / skills model, sorted by **duration and retrieval**. Adopted: the sorting axis, and
"rules cite their own case history." Not adopted: the `brain` vocabulary.

Ratifying this entry obsoletes the "ADR-0000 register rule" bullet in
`engineering.memento/CLAUDE.md` and requires re-pointing `adr-alignment`'s grep instructions at
`docs/decisions/`. Migration of the six legacy registers is decided separately in
[legacy-register-migration](2026-08-30-legacy-register-migration.md).
