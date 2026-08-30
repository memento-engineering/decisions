---
status: accepted
date: 2026-08-30
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: madr-profile
  surfaces:
    - "SPEC.md"
    - "schema/**"
    - "templates/**"
  obsoletes: []
  updates: [the-decision-register]
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# The entry format is a MADR profile, not a bespoke schema

## Context and Problem Statement

[the-decision-register](2026-08-29-the-decision-register.md) established the model but left the
concrete entry format to be invented. Before inventing one we surveyed the ecosystem: MADR 4.0
(2,431 stars, active, dual MIT/CC0), ~25 ADR CLIs, `archgate` (ADRs as executable TypeScript rules
with a Claude Code plugin), Backstage's multi-repo ADR plugin, and the IETF's RFC header model.

MADR is the de-facto standard and its conventions already match choices made here independently —
`docs/decisions/` as the path, YAML front matter for status. But MADR is **a template, not a
schema**: front matter is prefaced "these are optional metadata elements, feel free to remove any
of them," the `minimal` variant has none at all, and there is no formal spec or required field.
Crucially, MADR's own `0009-support-links-between-adrs` weighed structured links and chose free
prose in "More Information", accepting "Bad, because parsing gets harder." Supersession is an
unstructured string inside `status`. The machine-readable layer we need is the layer MADR
deliberately declined to build.

## Considered Options

* Invent a bespoke format
* Adopt MADR wholesale
* Adopt `archgate`
* A MADR **profile**: MADR's vocabulary and sections, plus a namespaced extension block

## Decision Outcome

**A MADR profile.** Our files are valid MADR; MADR files are not necessarily valid here.

* **Borrowed unchanged:** the `docs/decisions/` path, YAML front matter, the RACI fields
  (`decision-makers` / `consulted` / `informed`), the body section names, and the **status
  vocabulary** — which carries our force states with no invention at all:
  binding→`accepted`, superseded→`superseded by <slug>`, vacated→`deprecated`, rejected→`rejected`.
  Binding-on-write states as: **entries are born `accepted`; this profile never uses `proposed`.**
* **Added in a `register:` block:** `spec`, `slug`, `surfaces`, `obsoletes`, `updates`,
  `obsoleted-by`, `updated-by`, `bead`, `legacy-id`. MADR ignores unknown keys, so compatibility
  runs one way — the correct direction.
* **Two supersession edges, after the IETF's RFC headers:** `obsoletes` (replaced entirely) and
  `updates` (substantively amended, original remains in force). The memento registers have been
  drawing this distinction in title prose all along with no field to put it in.
* **Body from MADR's `bare-minimal` variant**, not the full template. The full one is
  options-analysis-heavy; an agent handed a "Considered Options" heading with no real options will
  manufacture some. Omit a section rather than invent content for it.
* **`archgate` rejected:** TypeScript/Bun rule authoring is the wrong ecosystem, and its
  enforcement point is static analysis over written code where ours is a committee lens grading a
  spec before code exists — a round earlier, which is the better point.

### Consequences

* Good, because we inherit vocabulary, recognizability and a license instead of inventing them.
* Good, because MADR's status values turned out to express force exactly, so there is no parallel
  `force` field to keep in sync with `status`.
* Neutral, because ecosystem tool compatibility (adr-log, ADR Manager, Backstage, the VS Code
  extension) is real but unlikely to be used here. It costs nothing and matters if this goes public.
* Bad, because we now track an upstream. A MADR 5.0 that renames fields is a spec bump for us.

### Confirmation

`madrlint` validates MADR shape per file and should run; it is not sufficient, being unaware of the
graph. `decisions lint` owns edge integrity, force-cache consistency, slug uniqueness, surface-glob
resolution and cross-register citation resolution.
