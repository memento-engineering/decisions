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
| `schema/` | JSON Schema for entry front matter and machine-readable output |
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
| 1 — CLI | `decisions index / search / lint / render / obsolete / update / vacate`, JSON out | an ecosystem impl |
| 2 — grid | overlay-installed skills, the committee lens, roster-wide cross-repo index and search, decision beads | a station |

## Search for precedent

Ask what already governs the work before acting. The bare tier searches the local register without
a station:

```sh
decisions search publish prerelease
# or, when composed by lunar
lunar decisions search publish prerelease
```

The grid tier runs the same reader over every mounted register in the fresh roster:

```sh
<station> decisions search publish prerelease
```

Search splits the query on whitespace and matches when **any** term is a case-insensitive
substring of a decision's title, slug or body, in that field precedence. Results are deliberately
unranked and sort by register then slug, so the same union produces the same citation order. A
migrated entry without a level-one ATX title remains searchable by slug and body.

Filters narrow the lexical matches. Repeat a filter for alternatives within that category;
different categories intersect:

```sh
decisions search --status accepted --decision-maker nico \
  --date-from 2026-09-01 --date-through 2026-09-30 \
  --slug prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only \
  --surface memento-engineering/engineering.memento/power_station/AGENTS.md \
  --updates agents-publish-prereleases-humans-promote-to-stable publish prerelease
```

The repeatable filters are `--status`, `--decision-maker`, `--slug`, `--surface`, `--obsoletes`,
`--updates`, `--obsoleted-by` and `--updated-by`; the two date bounds are single and inclusive.
Slugs and edge references compare exactly, decision-maker names compare case-insensitively and
exactly, and `--surface` takes a roster-qualified path matched against the authored surface globs.
Status selectors are ergonomic aliases over the unchanged MADR values:

| `--status` | raw hit `status` |
|---|---|
| `accepted` | `accepted` |
| `obsoleted` | `superseded by <slug>` |
| `vacated` | `deprecated` |
| `rejected` | `rejected` |

Add `--json` for newline-delimited JSON: one schema-1 hit object per line, with exactly `spec`,
`slug`, `register`, `path`, `status`, `date`, `field` and `snippet`. There is no wrapper and never
an all-register dump. Snippets contain one matching line and are at most 160 characters, counting
leading and trailing ellipses. Parse diagnostics go to standard error, so incomplete coverage is
not mistaken for a clean zero-hit result.

## What is ours

Borrowed deliberately: MADR's vocabulary, sections, path and status values (MIT/CC0); the IETF's
`Obsoletes`/`Updates` distinction.

Ours, because nothing in the ecosystem does it — **binding-on-write with a docket** (every ADR tool
assumes proposed → review → accepted), **cross-repo union over a live roster**, and **decisions
linked to the work graph**.

## Status

The format is settled at spec 1 and self-hosted in [`docs/decisions/`](docs/decisions).

All three tiers are built. Tier 0 works today by copying `templates/`. Tier 1 is the Dart engine
in [`cli/dart/decisions/`](cli/dart/decisions) — `index`, `search`, `lint`, `migrate-legacy`,
`obsolete`, `update`, `vacate`. Tier 2 is
[`grid_assets/decisions_grid_assets/`](grid_assets/decisions_grid_assets), which installs the
`decide` and `ratify` skills, vends the `decision-alignment` rubric, and composes a
`<station> decisions` command over a live roster.

Neither Dart package is published to pub.dev yet (`publish_to: none`); consume them by git ref, or
vendor `cli/dart/decisions` directly. A tier-1 implementation in another ecosystem is unbuilt —
the format is specified so that it does not have to be Dart.
