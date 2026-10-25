---
status: accepted
date: 2026-10-24
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: the-decisions-binary-carries-its-own-agent-instructions
  surfaces:
    - "cli/dart/decisions/lib/src/instructions_command.dart"
    - "cli/dart/decisions/lib/src/guide.dart"
    - "cli/dart/decisions/lib/src/guides.g.dart"
    - "cli/dart/decisions/tool/generate_guides.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by:
    - a-skill-stub-names-its-fallback-when-the-decisions-binary-is-missing
  bead: dec-mtj
  legacy-id: null
---

# The decisions binary carries its own agent instructions

## Context and Problem Statement

A tier-1 adopter could install the `decisions` binary, but its agent still had to find the
`decide` and `ratify` skills somewhere else: copy them out of this repo by hand, or run a station
whose overlay installs them. A hand-copied skill drifts from the engine the moment either moves,
and the agent has no way to tell which version of the instructions matches the binary that will
lint its work. The binary had no way to explain itself to an agent arriving cold.

The org already settled how a tool should do that:
`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help` (a short `prime`,
then a bounded `--help` per verb), and
`memento-engineering#knowledge-lives-in-the-smallest-surface-that-can-enforce-it`, which puts the
instructions in the artifact that runs them rather than beside it.

## Decision Outcome

**The binary is the delivery vehicle for its own agent instructions.** A tier-1 adopter installs
the binary and adds one line to `AGENTS.md` pointing at `decisions prime`; nothing else is copied.

1. **`skills/` stays the one source.** `tool/generate_guides.dart` renders every
   `skills/<name>/SKILL.md` (name and description from its front matter, then its body) into
   `lib/src/guides.g.dart`. A test fails while the generated file is stale, so a skill edit cannot
   ship without reaching the binary.
2. **`decisions prime`** is the orientation: what a register is, where this one lives, whether it
   has a `STYLE.md`, each verb with when to reach for it, and pointers to `guide` and
   `<verb> --help`. It never restates a verb's contract, and it says plainly when the register is
   missing. It lists the verbs its host actually carries, so a new verb appears without editing it.
3. **`decisions guide [topic]`** lists the guides, or prints one skill body followed by the
   register's own `STYLE.md` under a heading that names the file. What `STYLE.md` is, and why the
   engine does not read it as an entry, is
   `decisions#a-registers-style-md-is-its-style-guide-and-uppercase-files-are-not-entries`: one per
   register, never inherited across the roster (nico, 2026-10-24). These verbs depend on it: an
   engine without it reads `STYLE.md` as a malformed entry and fails `decisions lint`.
4. **`decisions skills install <dir>`** writes `<dir>/<name>/SKILL.md` stubs for agents that load
   skills from a directory. A stub carries the canonical front matter and says only to run
   `decisions guide <name>`; a marker line identifies it. Install overwrites its own stubs and
   refuses, exiting 1 and writing nothing, when any other file is in the way.
5. All three are ordinary verbs, wired once for both hosts: the standalone binary and the grouped
   `<station> decisions` command.

The scope ruling (nico, 2026-10-24) ships these three now; a `decisions new` verb and a slimmer
`decide` skill that leans on it follow separately, and `ratify` is slimmed later.

### Consequences

* Good, because the instructions an agent reads always match the engine that lints its work: both
  come from the same binary and the same version.
* Good, because an adopter with no station and no copy of this repo gets the skills from one
  install and one line of `AGENTS.md`.
* Good, because a stub is a pointer, not a copy, so reinstalling is never needed to pick up a new
  skill body, only a new skill.
* Bad, because a skill edit now needs a regeneration step in `cli/dart/decisions`, and the new
  text reaches adopters only with the next release of the binary.
* Bad, because `guide` prints the whole skill body; a long skill costs its full length in an
  agent's context every time it is read.
