---
status: accepted
date: 2026-09-10
decision-makers: [nico, refiner]
consulted: []
informed: [governor]
register:
  spec: 1
  slug: agents-publish-prereleases-humans-promote-to-stable
  surfaces:
    - "engineering.memento/*/CLAUDE.md"
    - "engineering.memento/*/AGENTS.md"
    - "engineering.memento/*/packages/*/extension/station_overlay/*/agents/*.md"
    - "engineering.memento/*/packages/*/extension/station_overlay/*/skills/release/SKILL.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: [prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only]
  bead: org-928
  legacy-id: null
---

# Agents publish prereleases; humans initiate promotion to stable

## Context and Problem Statement

Publishing prereleases and promoting to stable carry different levels of irreversibility.

## Decision Outcome

Agents may publish prereleases freely. Promotion to stable is a human-initiated act.

### Consequences

* Good, because release work does not pause for authority already granted.
