---
status: accepted
date: 2026-09-10
decision-makers: [nico, refiner]
consulted: []
informed: [governor]
register:
  spec: 1
  slug: prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only
  surfaces:
    - "engineering.memento/*/CLAUDE.md"
    - "engineering.memento/*/AGENTS.md"
    - "engineering.memento/*/packages/*/extension/station_overlay/*/agents/*.md"
    - "engineering.memento/*/packages/*/extension/station_overlay/*/skills/release/SKILL.md"
  obsoletes: []
  updates: [agents-publish-prereleases-humans-promote-to-stable]
  obsoleted-by: null
  updated-by: []
  bead: org-6ku
  legacy-id: null
---

# Prerelease rungs are dev, beta, rc — and only a human PROMOTES to rc

## Context and Problem Statement

The prerelease policy needs named rungs and a durable authority boundary.

## Decision Outcome

Prereleases progress through dev, beta, and rc. Only a human promotes a package to rc.

### Consequences

* Good, because every prerelease label has one meaning.
