# decisions

The decision-register pattern, packaged so any repo can adopt it — and memento's reference
implementation.

A register is a directory of markdown files under `docs/decisions/`, one file per decision,
modelled as **a citation graph with force** rather than a document tree. Consolidated `ADR`-style
documents are rendered views over the graph, not destinations.

The entry format is a **[MADR](https://github.com/adr/madr) 4.0 profile** — MADR's vocabulary,
sections and status values, plus a `register:` block carrying the machine-readable layer MADR
deliberately does not provide (typed supersession edges, governed surfaces, a format version).
Our files are valid MADR; MADR files are not necessarily valid here.

The format **degrades to grep**: a repo with no tooling, no Dart and no station adopts the pattern
by copying `templates/` and writing files.

| | |
|---|---|
| [`SPEC.md`](SPEC.md) | the format — front matter, force, edges, versioning, the docket |
| `schema/` | JSON Schema for entry front matter |
| `templates/` | entry + rendered-view templates |
| `skills/` | the judgement half — language-neutral markdown |
| `rubrics/` | `decision-alignment`, the committee lens |
| `docs/decisions/` | this repo's own register (self-hosted) |
| `cli/dart/` | the deterministic engine — no grid dependency |
| `grid_assets/` | the grid adapter — installs skills, vends the rubric, composes `<station> decisions` |

## Tiers

| Tier | What you get | Needs |
|---|---|---|
| 0 — prose | format, templates, a greppable register, skills as plain markdown | nothing |
| 1 — CLI | `decisions index / lint / render / obsolete / update / vacate`, JSON out | an ecosystem impl |
| 2 — grid | overlay-installed skills, the committee lens, roster-wide cross-repo index, decision beads | a station |

## What is ours

Borrowed deliberately: MADR's vocabulary, sections, path and status values (MIT/CC0); the IETF's
`Obsoletes`/`Updates` distinction.

Ours, because nothing in the ecosystem does it — **binding-on-write with a docket** (every ADR tool
assumes proposed → review → accepted), **cross-repo union over a live roster**, and **decisions
linked to the work graph**.

## Status

The format is settled at spec 1 and self-hosted in [`docs/decisions/`](docs/decisions). Not yet
built: the CLI, the grid asset pack, the skills, and the rubric.
