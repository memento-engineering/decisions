---
status: accepted
date: 2026-01-01
decision-makers: [fixture]
register:
  spec: 1
  slug: no-file-watching
  surfaces: ["*/packages/grid/**"]
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# No file watching

## Decision Outcome

Do not introduce file-system watchers beneath `packages/grid/**`; dependencies
are observed through the resident tree.
