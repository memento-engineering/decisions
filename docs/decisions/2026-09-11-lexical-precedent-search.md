---
status: accepted
date: 2026-09-11
decision-makers: [nico, architect]
consulted: []
informed: []
register:
  spec: 1
  slug: lexical-precedent-search
  surfaces:
    - "README.md"
    - "SPEC.md"
    - "schema/decision-search-hit.schema.json"
    - "cli/dart/decisions/**"
    - "grid_assets/decisions_grid_assets/**"
  obsoletes: []
  updates: [the-decision-register]
  obsoleted-by: null
  updated-by: []
  bead: dec-5q9
  legacy-id: null
---

# Decision search is OR-token lexical, unranked, and bounded

## Context and Problem Statement

The register can be indexed and maintained, but an agent asking whether a course of action was
already decided has no lookup. `decisions index` emits the entire register for a caller to filter,
and bead-store search cannot see a register document that has no bead. In practice an agent missed
two accepted prerelease rulings in its search results, escalated authority the register had already
granted, and found the decisions later only through an unrelated filesystem grep.

A precedent reader must work in the bare CLI without station state, compose over the grid's live
roster, preserve the MADR profile's raw force vocabulary, and remain deterministic enough to cite.

## Considered Options

* Exact-phrase matching over each register document
* Conjunctive lexical terms, requiring every query term to match
* Disjunctive lexical terms, matching when any query term occurs
* Scored relevance ranking across lexical or embedding matches

## Decision Outcome

`decisions search` uses **case-insensitive OR-token lexical matching** across title, slug and body,
in that field precedence. It splits a trimmed query on whitespace, returns a decision when any term
is a substring, and does not relevance-rank. Hits sort by register then slug.

The bare command reads `docs/decisions`; the grid adapter composes the same parser-backed service
over every mounted register in the fresh roster. Search reuses the index's tolerant register union,
entry parser, spec-range checks, graphs and governed-surface matching rather than defining another
document reader.

Filters intersect across categories and treat repeated values within one category as alternatives.
They cover raw-status aliases, inclusive dates, decision-makers, slugs, governed surfaces and all
four authored or cached edge fields. Every hit preserves the raw MADR status: `accepted`,
`superseded by <slug>`, `deprecated` or `rejected`.

`--json` emits newline-delimited schema-1 hit objects, one object per match and no wrapper. A hit
contains only its output spec, slug, register, path, raw status, date, winning field and snippet.
The snippet is one matching line and is at most 160 characters, including both clipping ellipses.

### Consequences

* Good, because an agent can find and cite governing precedent before asking for authority or
  inventing another policy.
* Good, because bare and roster lookup cannot drift into different parsing or filter semantics.
* Bad, because OR terms favor recall over precision and can return matches for only one broad term.
* Bad, because deterministic unranked output leaves result prioritization to the reader.

## More Information

The inspected `power_station` bead-store search is prior art for splitting a query into OR terms and
extracting a single-line 160-character window around the earliest match. This decision adopts
those retrieval ergonomics, not its storage or parser seam: decision search reads register Markdown
through the decisions engine and filters raw MADR fields. It does not duplicate or depend on the
bead-search parser, bead export, or semantic index.
