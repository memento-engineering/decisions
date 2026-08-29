# The `decisions` format

**Status:** DRAFT. The constitutive decision is `docs/decisions/0001-the-decision-register.md`,
which is itself unratified. Open questions are marked **OPEN** inline; nothing below is settled
until 0001 is ratified.

A decision register is a directory of markdown files. Each file is one decision. The format is
plain markdown with YAML front matter and **must degrade to grep**: a repo with no tooling, no
Dart, and no station can adopt the pattern by copying `templates/` and writing files. Tooling
makes the register mechanical; it is never required to make it readable.

## The model

A register is **a citation graph with force**, not a document tree.

- Every decision carries **force** the moment it is recorded. Force is a property of the entry,
  not of where it lives.
- Decisions carry **edges** to each other and to the surfaces they govern.
- Human-readable consolidated documents (what the org calls `ADR-000N` today) are **rendered
  views** over the graph — generated, never authored, never a destination.

This replaces the promote-into-a-better-document model. Codification is compaction, not
authorization.

## Location

Registers live at `docs/decisions/` in each adopting repo. Rendered views live at
`docs/decisions/views/`.

**OPEN:** the migration path for existing `docs/adr/ADR-0000-*.md` registers (six of them,
~189 amendments, ~50 pending). Rename, dual-home during a cutover, or leave legacy in place and
start fresh — undecided.

## Entry file

`docs/decisions/NNNN-kebab-slug.md`, `NNNN` zero-padded and repo-local, allocated in order.

```yaml
---
id: 0007
title: One sentence, declarative, states the decision and not the topic
date: 2026-08-29
decider: nico | agent | agent+nico
force: binding | superseded | vacated | rejected
bead: pow-lq6                      # optional — the work this arose from
surfaces:                          # governs-surface edges; paths or symbols
  - packages/grid_assets/lib/src/code/
supersedes: [0003]                 # this entry replaces those
superseded_by: null                # set when something replaces this
vacated_by: null                   # set when force becomes `vacated`
cites: [the_grid#0050]             # cross-repo: <repo>#<id>
---

## Decision
## Why
## Surfaces
```

`decider` is a **field, never a location.** A decision made with a human in the loop is recorded
the same way as an autonomous one, with `decider` telling the truth. The prior rule sorted by
authorship and prescribed silence for human-decided rulings; that is what lost them.

## Force

| force | meaning |
|---|---|
| `binding` | in effect; binds new work |
| `superseded` | replaced by a named successor; `superseded_by` required |
| `vacated` | withdrawn; `vacated_by` required |
| `rejected` | should not have been recorded; carries no force and never did |

**Binding on write.** A decision has force from the moment it is recorded, by anyone. There is no
pending state and no human gate on *recording*. The human gate is on **force changes** —
superseding, vacating, rejecting — which happen at a docket.

**OPEN (the load-bearing one):** binding-on-write is clause 3 of entry 0001 and needs Nico's
ruling. Everything else in this spec assumes it.

## Vacating

Vacating is a first-class operation, not an edit. It **requires a successor**: either a
replacement decision, or an explicit entry recording that no rule governs the surface any more.
Silence is not a valid outcome of a vacate.

Vacating fires two consequences off the `surfaces` edges: open work whose design touches those
surfaces is flagged for re-validation, and the reversal work can be filed against the affected
repos.

## The docket

The human-agent ratification event. Triggered by signal, never by calendar: register size, a
detected contradiction, a decision cited N times, or a pending vacate request. It produces a
worksheet — one row per decision needing a force change — and the dispositions are themselves
entries with `decider: nico`.

**OPEN:** the trigger thresholds.
