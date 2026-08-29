# decisions

The decision-register pattern, packaged so any repo can adopt it — and the memento org's
reference implementation.

A register is a directory of markdown files under `docs/decisions/`, one file per decision,
modelled as **a citation graph with force** rather than a document tree. Consolidated
`ADR`-style documents are rendered views over the graph, not destinations.

The format **degrades to grep**: a repo with no tooling, no Dart, and no station adopts the
pattern by copying `templates/` and writing files.

| | |
|---|---|
| `SPEC.md` | the format — front matter, force states, edges, the docket |
| `templates/` | entry + rendered-view templates |
| `skills/` | the judgement half — language-neutral markdown |
| `rubrics/` | `decision-alignment`, the committee lens |
| `docs/decisions/` | this repo's own register (self-hosted) |
| `cli/dart/` | the deterministic engine — no grid dependency |
| `grid_assets/` | the grid adapter — installs skills + rubric, composes `<station> decisions` |

## Tiers

| Tier | What you get | Needs |
|---|---|---|
| 0 — prose | format, templates, greppable register, skills as plain markdown | nothing |
| 1 — CLI | `decisions index/lint/render/supersede/vacate`, JSON out | an ecosystem impl |
| 2 — grid | overlay-installed skills, the committee lens, roster-wide cross-repo index | a station |

**Status:** DRAFT throughout. Nothing is settled until
[`0001`](docs/decisions/0001-the-decision-register.md) is ratified.
