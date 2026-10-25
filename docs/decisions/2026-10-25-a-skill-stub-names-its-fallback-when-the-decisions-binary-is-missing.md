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
  slug: "a-skill-stub-names-its-fallback-when-the-decisions-binary-is-missing"
  surfaces:
    - "cli/dart/decisions/lib/src/instructions_command.dart"
  obsoletes: []
  updates:
    - "the-decisions-binary-carries-its-own-agent-instructions"
  obsoleted-by: null
  updated-by: []
  bead: "dec-2ow"
  legacy-id: null
---

# A skill stub names its fallback when the decisions binary is missing

## Context and Problem Statement

`decisions skills install` writes a `SKILL.md` stub whose only instruction is to run
`decisions guide <name>`. An agent that loads the stub on a machine where the binary is missing
is left with a pointer to a command that does not run, and no way to record a decision at all.
`the-decisions-binary-carries-its-own-agent-instructions` fixed a stub's contents as that one
instruction, and its body is immutable.

The register itself never needs the binary: the format degrades to grep, and
`decisions-new-owns-the-write-mechanics` keeps a tier-0 fallback in the `decide` skill, from
`templates/decision.md` and `SPEC.md`. The stub is the one surface an agent reads before it has
any of that, so it is where the fallback has to be named.

## Decision Outcome

**A skill stub names its fallback for a missing binary, in one line.** After the instruction to
run `decisions guide <name>`, every stub `skills install` writes ends with a single fallback line:
if `decisions` is not installed, install it (`brew install memento-engineering/tap/decisions`, or
a pinned release download from the project's releases page) or follow `templates/decision.md` and
`SPEC.md` from that repository.

This amends point 4 of `the-decisions-binary-carries-its-own-agent-instructions`, which stays in
force: a stub still carries the canonical front matter and the marker line, still defers to
`decisions guide <name>` for every instruction, and install still overwrites only its own stubs.
The fallback is the only other thing a stub says. It is one line, not a copy of the guide, so a
stub stays a pointer (nico, 2026-10-24).

### Consequences

* Good, because an agent holding only a stub can still install the engine or record by hand,
  instead of stopping at a command that does not run.
* Good, because the fallback names the same tier-0 sources the `decide` skill falls back to, so
  the two never disagree about what to do without the binary.
* Bad, because the stub's bytes changed: a stub written by an earlier install lacks the line until
  the adopter reinstalls.
