---
status: accepted
date: 2026-10-24
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: decisions-new-owns-the-write-mechanics
  surfaces:
    - "cli/dart/decisions/lib/src/record.dart"
    - "cli/dart/decisions/lib/src/new_command.dart"
    - "skills/decide/SKILL.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-dmq"
  legacy-id: null
---

# decisions new owns the write mechanics; the decide skill owns judgement

## Context and Problem Statement

The `decide` skill carried every mechanical step of recording a decision as shell an agent had to
transcribe: a slug regex in `awk`, a collision grep in `rg`, a date from `date`, a hand-filled YAML
template whose quoting the agent had to get right, and a lint run after the file already existed.
Each step was a place to drift from `SPEC.md`, and a malformed or colliding entry was caught only
once it was on disk. The engine already owned the same checks for lint and for the force verbs;
the skill was a second, unenforced copy of them.

Knowledge belongs in the smallest surface that can enforce it
(`memento-engineering#knowledge-lives-in-the-smallest-surface-that-can-enforce-it`). Shape,
identity and first-write cleanliness are deterministic, so the engine can enforce them; what to
record, which surfaces a ruling governs, which edges it carries and who decided cannot be checked
by a program. On 2026-10-24 nico ruled the scope of the wider change: `decisions new` plus a slim
`decide` now, `ratify` later.

## Decision Outcome

**`decisions new <slug>` owns the write mechanics; the `decide` skill owns judgement.**

1. **One verb, both hosts.** `new` is wired into the shared verb list, so the standalone
   `decisions` binary and a composed `<station> decisions` group expose the same command. Its
   `--help` is bounded and names the required inputs
   (`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help`).
2. **Inputs.** `--title`, `--body <path|->` (the Markdown after the H1), at least one `--surface`
   and at least one `--decision-maker` are required. `--consulted`, `--informed`, `--obsoletes`
   and `--updates` repeat; `--bead` defaults to null, `--date` to today in local time,
   `--register` to `docs/decisions`, `--repo-root` to `.`; `--roster` resolves `<repo>#<slug>`
   edges exactly as the force verbs do. A missing required input is a usage error.
3. **Refusals, in order, each exiting 1 with nothing written:** a slug that is not kebab-case of at
   most 80 characters; a slug any entry in the register already holds, or a target file that
   already exists, named so the author can cite it instead; a body with an H1 of its own or
   without level-two `Context and Problem Statement` and `Decision Outcome` sections; a qualified
   edge naming the entry's own register; and any lint diagnostic against the new file when a copy
   of the register plus the new entry is linted the way force mutations lint their candidates —
   same origin-register shape, same roster, roster-wide surfaces exempt. Dirt elsewhere in the
   register is not this write's to fix and does not block it.
4. **Birth values are written, never typed.** `status: accepted`, `spec: 1`, `obsoleted-by: null`,
   `updated-by: []`, `legacy-id: null`; every free-text value is a double-quoted scalar. The
   register directory is created when absent.
5. **Edges are completed by a separate act.** The verb prints the written path, the `repo#slug`
   handle, and one `next:` line per authored edge naming the force verb that writes the target's
   cache (`decisions update <target> --by <slug>`, `decisions obsolete <target> --by <slug>`). A
   target in another register is named with the register to run in and the qualified successor.
   `new` never rewrites another entry, keeping the separate-acts rule in `SPEC.md`.

The skill keeps what a program cannot check: whether to record, deriving governed surfaces from
the change, honest authorship, the meaning of an edge, and minting the decision bead before citing
it.

### Consequences

* Good, because a malformed, colliding or unlinted entry is refused before it exists, by the same
  engine that lints the register, instead of being caught after the fact.
* Good, because the skill can shrink to judgement and stop restating checks that drift.
* Bad, because a register with no CLI still records by hand from `templates/`, so the skill must
  keep a tier-0 fallback until every consumer composes the verb.
