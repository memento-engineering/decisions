---
status: accepted
date: 2026-10-25
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "templates-style-md-is-the-starter-style-guide-for-a-register"
  surfaces:
    - "templates/STYLE.md"
    - "docs/decisions/STYLE.md"
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-1ee"
  legacy-id: null
---

# templates/STYLE.md is the starter style guide for a register

## Context and Problem Statement

`a-registers-style-md-is-its-style-guide-and-uppercase-files-are-not-entries` gave a register a
place for its prose style, and `the-decisions-binary-carries-its-own-agent-instructions` hands
that `STYLE.md` to a writer after every guide. An adopter still had nothing to start one from:
`templates/` held an entry and a view and no style guide, so each register wrote its first guide
from a blank page, and this repo, which self-hosts the pattern, had no `STYLE.md` of its own for
`guide decide` to print. The README taught an agent the verbs but not where house style lives.

On 2026-10-24 nico ruled the scope of the wider change: user docs only, a short starter guide in
`templates/`, this repo's own guide, and a README that teaches a tier-1 agent the register.

## Decision Outcome

**`templates/STYLE.md` is the starter style guide for a register: an adopter copies it to
`docs/decisions/STYLE.md` and edits it.**

1. **Guidance, never format.** The starter covers titles, voice, section habits, length and
   citing. Nothing in it is parsed: it carries no front matter and states no rule the CLI checks,
   so the format still degrades to grep, and a register that never copies it loses nothing.
2. **Copied, not inherited.** The starter is a template like `decision.md`, not a default the
   engine falls back to. A register without a `STYLE.md` has no style guide, exactly as the
   no-inheritance ruling (nico, 2026-10-24) requires.
3. **This register keeps its own.** `docs/decisions/STYLE.md` describes how entries here are
   actually written, read off the existing entries rather than invented. Where the earliest
   entries depart from it, it follows the recent ones and says so.
4. **The README teaches a tier-1 agent in one place.** After installing the binary, an adopter
   adds one line to `AGENTS.md` pointing at `decisions prime`, optionally runs
   `decisions skills install`, and copies the starter for house style. The README links `SPEC.md`
   for the rule rather than restating it, keeping user docs apart from maintainer detail
   (`memento-engineering#maintainer-and-user-docs-are-separate`).

### Consequences

* Good, because an adopter's first style guide starts from a shape that already matches the
  sections `SPEC.md` fixes, and `guide decide` prints it to every writer from then on.
* Good, because this repo now exercises its own style-guide path end to end.
* Bad, because a copied starter drifts from the template the moment either is edited, and nothing
  tells the adopter that the template has changed.
