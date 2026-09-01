# decision-alignment

Does the spec respect every recorded decision that governs its touched surfaces
across the station's live roster? Each mounted substation keeps its register at
`docs/decisions/`. Every recorded decision binds. There is no pending state. A
spec that touches a surface those decisions govern must cite the relevant
decision and either implement it, extend it, or explicitly propose overriding
it. A spec that silently contradicts a recorded decision is the most expensive
failure this committee can miss: it undoes deliberated work, usually unnoticed
until the contradiction ships.

Decision citations use the canonical `<repo>#<slug>` identity, for example
`the_grid#admission-authority-boundary`. A migrated entry may also carry
`register.legacy-id`; the old id still resolves, but the grading rationale must
include the canonical `<repo>#<slug>` returned by the index so an offending
precedent is unambiguous across registers.

You are blind to the other lanes' concerns (fit, testability, plan detail) —
weigh ONLY decision alignment.

## Before grading: query governing decisions

Lookup belongs to the deterministic command; judgement stays in this rubric.
Do not enumerate files or infer candidates from title keywords. Read every
literal path in the spec's `## Touches` section, prefix each repository-relative
path with its substation repository name, and invoke the composing station's
runner once per unique roster-qualified path:

```sh
<station> decisions index --surface <repo>/<path>
```

Call roster mode with no explicit register-directory arguments. That omission
is load-bearing: the grid adapter resolves the live mounted-substation roster
and the command returns the union rather than only the current repo's register.
Parse the structured JSON `decisions` array and retain results from every
`originRegister`; a sibling register has exactly the same force as the local
one.

For each returned record, read the selected entry under its `originPath`, which
is a `docs/decisions/` directory, by matching the returned `slug`:

```sh
grep -Erl --include='*.md' '^[[:space:]]*slug:[[:space:]]*<slug>[[:space:]]*$' '<originPath>'
```

This grep resolves an entry the index already selected. It must not become a
keyword search for additional candidates. Read every resolved entry, quote the
load-bearing clause, and record the queried surface paths in the rationale so a
claim that no decision applies is verifiable. An empty `decisions` array for
every touched path means no recorded decision governs the spec's surfaces; do
not manufacture a citation.

## Bands

- **A** — the spec's `## ADR Alignment` section cites every load-bearing
  decision by its `<repo>#<slug>` identity, with a one-sentence quote of the
  constraining clause, and states how the plan aligns (or how it extends the
  decision, by name). Where no decision applies, the section says so explicitly
  with the roster-qualified surface paths that verified it.
- **B** — the relevant decision is cited, but without the load-bearing clause:
  a reader can tell WHICH decision is implemented but not which clause
  constrains the work.
- **C** — the spec is clearly downstream of a recorded decision (it extends a
  surface the decision established) but never cites it; the alignment is
  accidental rather than acknowledged. Or: the section claims "no decision
  applies" without naming the roster-qualified surface paths that verified it.
- **D** — `decisions index` returns a decision that plainly governs a surface
  this spec touches, and the spec does not cite it. The fix is mechanical — add
  the citation with the quoted clause and apply (or explicitly distinguish) the
  precedent — so this routes to spec rework, not a human.
- **F** — a structural contradiction: the spec, AS WRITTEN, would invert or
  undo a load-bearing clause of a recorded decision, and no citation paragraph
  can fix it — implementing the spec means the precedent no longer holds. The
  route parks the bead at a gate; revisiting a precedent is a human call
  (supersede the decision, or rework the spec to align).

## Calibration

- Every recorded decision binds for grading. There is no pending class to
  promote or discount.
- Do not demand citations for decisions that genuinely do not touch the spec's
  surfaces — a padded alignment section citing everything is noise, not
  alignment. The A-grade signal is the LOAD-BEARING citation, quoted.
- Cross-register origin never weakens force. In the fixture roster,
  `policy_repo#no-file-watching` governs `*/packages/grid/**`. A spec touching
  `source_repo/packages/grid/lib/src/watcher.dart` and adding `Directory.watch`
  structurally contradicts its "Do not introduce file-system watchers" clause:
  grade **F** and cite `policy_repo#no-file-watching` in the rationale. A
  local-register-only result is invalid because the command must query the
  roster union.
- The companion fixture touches `source_repo/README.md`; its surface query
  returns an empty `decisions` array. It
  must not be penalised for citing no decision when its `## ADR Alignment`
  section records that queried path; that
  is the no-precedent form of grade **A**.
- The org invariants (the seam word is **extension**, never the banned
  alternative; package names are human faculties, never agent-nouns; `bd` CLI
  only, never SQL) count as recorded decisions when their surface globs match.
