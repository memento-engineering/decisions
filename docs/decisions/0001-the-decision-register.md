---
id: 0001
title: A decision register is a citation graph with force, recorded by anyone and ratified at a docket
date: 2026-08-29
decider: agent+nico
force: binding
bead: null
surfaces:
  - SPEC.md
  - docs/decisions/
  - engineering.memento/CLAUDE.md
supersedes: []
superseded_by: null
vacated_by: null
cites: []
---

> **DRAFT — not ratified.** This entry is the constitutive decision of the pattern and is
> deliberately the first exercise of it. Clause 3 is the open ruling.

## Decision

1. **Every repo keeps a register at `docs/decisions/`** — one markdown file per decision, plain
   front matter, greppable with no tooling. Consolidated `ADR`-style documents become **rendered
   views** at `docs/decisions/views/`, generated from the graph.

2. **Authorship is a field, not a location.** Autonomous decisions and human rulings are recorded
   identically; `decider` distinguishes them. The prior rule (org `CLAUDE.md`, "The ADR-0000
   register rule") sorted by authorship and told agents *not to record* human-decided rulings —
   the highest-authority class in the org — which is why they were lost to prose and reconstructed
   after the fact.

3. **A decision binds on write.** Force attaches when the entry is recorded, by anyone, in any
   session. There is no `pending` state. *(This clause is the ruling this entry needs.)*

4. **The human gate is on force changes, not on recording.** Superseding, vacating, and rejecting
   happen at a **docket**, triggered by signal rather than calendar.

5. **Vacating requires a successor.** A withdrawn decision names its replacement or explicitly
   records that no rule governs the surface. Silence is not a valid outcome.

6. **The pattern ships as three tiers** — prose (nothing required), CLI (an ecosystem
   implementation), grid (a station-installed asset pack). The grid tier is the best-supported,
   never the only one.

## Why

The register the org runs today works, and its committee lens (`adr-alignment`) is load-bearing —
it catches real contradictions. But four properties broke down in practice, all traceable to the
same root: **the format sorts by authorship and stores prose, where it should sort by force and
store a graph.**

- **Promotion buys nothing, so it never happens.** The rubric already treats pending amendments as
  binding, so promotion is documentation hygiene, not authorization. `power_station` carries 16
  pending and has promoted zero, ever; the org has recorded exactly one ratification round
  (genesis, 2026-06-13). A ceremony with no operational payoff loses to entropy.
- **The record is inverted.** ~6 KB essays for autonomous decisions; nothing durable for Nico's
  rulings. genesis is the only register annotating `decider:` — and the only one that ratified.
- **The format cannot express supersession.** `power_station` A25/A26/A27/A30 narrate retirement,
  re-homing, and reversal in *title prose*. the_grid A53 is the failure case: a round wired work in
  direct contradiction of A52's recorded disposition and had to be hand-reverted.
- **Registers are repo-local; decisions are org-wide.** `pow-lq6` (P1): a space_station bead carried
  a file-watcher through a **grade-A** `adr-alignment` because the_grid's A50 lived in a register
  the lens structurally could not reach.

Prior art consulted: Steve Yegge, *The Shape of Things to Come* — the layered `brain/` / `doc/` /
beads / `bd remember` / skills model, sorted by **duration and retrieval**. Adopted: the sorting
axis, and "rules cite their own case history." Not adopted: the `brain` vocabulary.

## Surfaces

Ratifying this entry obsoletes the "ADR-0000 register rule" bullet in `engineering.memento/CLAUDE.md`
and requires re-pointing `adr-alignment`'s grep instructions at `docs/decisions/`. The migration of
the six existing registers is **not** decided here.
