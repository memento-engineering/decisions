---
status: accepted
date: {YYYY-MM-DD}
decision-makers: []
consulted: []
informed: []
register:
  spec: 1
  slug: {kebab-slug, unique in this register, matching the filename}
  surfaces:
    - "{glob or path this decision governs}"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# {short title, declarative — state the decision, not the topic}

## Context and Problem Statement

{Two to three sentences. What forced the decision, and what was constrained.}

<!-- Optional. Include ONLY if options were genuinely weighed. Omit rather than invent. -->
## Considered Options

* {option}

## Decision Outcome

{What was decided, stated so a reader can comply without reading further.}

### Consequences

* Good, because {…}
* Bad, because {…}

<!-- Optional. -->
### Confirmation

{How compliance is checked — a lint rule, a test, a committee lane.}
