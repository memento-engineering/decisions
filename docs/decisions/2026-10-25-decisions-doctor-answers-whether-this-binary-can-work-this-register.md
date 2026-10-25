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
  slug: "decisions-doctor-answers-whether-this-binary-can-work-this-register"
  surfaces:
    - "cli/dart/decisions/lib/src/doctor.dart"
    - "cli/dart/decisions/lib/src/doctor_command.dart"
    - "schema/doctor-result.schema.json"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-2nx"
  legacy-id: null
---

# decisions doctor answers whether this binary can work this register, for any harness

## Context and Problem Statement

Whatever runs the `decisions` binary for an adopter (a harness's own health check, CI, a human at a
terminal) needs one answer before trusting it with a register: can this binary, at this version,
work this checkout? Until now each caller had to piece that together from `--version`, a full
`lint` and a hand comparison of installed skill stubs. A full lint answers a different question: it
reports graph findings an adopter may be mid-way through fixing, and it does not look at skill
stubs at all. The failures that actually strand an agent are narrower. The register is missing, an
entry declares a spec newer than the binary reads, an entry does not parse, or a stub points at a
guide the binary no longer carries.

`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help` already asks every
verb for a bounded `--help`. A health check is the verb a shim calls before anything else, so its
output has to be a contract a shim can rely on, not prose it has to scrape.

## Decision Outcome

**`decisions doctor` answers whether this binary can work this register, and it knows nothing about
who is asking.** Any harness that wants a health check shims over it; the binary never learns a
harness. It has no flag, output format, environment variable or name for any particular harness,
in code, help or output (nico, 2026-10-24).

1. **Checks**, each reported as `ok`, `warn`, `fail` or `info` with a one-line reason and, where
   there is something to do, a one-line fix:
   * `binary` (info): the version and the spec it reads and writes;
   * `register`: the register directory exists (fail when absent, with a hint to start one with
     `decisions new`);
   * `spec`: every entry declares a spec this binary reads (fail otherwise, with a hint naming
     `brew install memento-engineering/tap/decisions` and the release download, the channels
     `memento-engineering#org-clis-ship-through-one-homebrew-tap` set). This is the reader rule of
     `decisions#spec-and-artifact-versioning` made checkable. An entry newer than the binary is a
     spec finding, never a parse finding, because a newer spec may add keys this binary rejects;
   * `parse`: every other entry parses. This is not a lint: graph findings stay with `decisions
     lint`, which the finding names;
   * `style` (info): whether the register has a `STYLE.md`;
   * `skills`, only with `--skills <dir>`, compared in both directions against what this binary's
     `skills install` would write: a stub naming a guide the binary lacks fails (a dead pointer); a
     stub that differs from what it would write, or a carried guide with no stub, warns. A
     `SKILL.md` without the stub marker is the adopter's own and is reported as info, never judged.
2. **`--no-register`** inspects no register, so a harness with no repository in its working
   directory can still check the binary and its stubs. `--register` (default
   `<repo-root>/docs/decisions`), `--repo-root` and `--json` complete the options.
3. **The output contract is fixed**, because shims depend on it. Exit 0 when every finding is `ok`
   or `info`, 1 when the worst is `warn`, 2 when it is `fail`, and 64 for a usage error as with every
   verb. The first stdout line is the worst finding, with `(and N more)` when N other findings are
   at `warn` or `fail`; one line per finding with its fix follows. Nothing reaches stdout before
   that line, and stderr carries only usage errors and crashes. `--json` emits a result pinned by
   `schema/doctor-result.schema.json` at `schemaVersion` 1, the way lint's result is pinned.
4. **Bounded and offline**: it reads files and nothing else, with no network and no subprocess,
   and finishes well under a second on a normal register.
5. It is an ordinary verb, wired once for both hosts, and `prime` lists it.

### Consequences

* Good, because every harness gets the same answer from the same binary, and a new harness costs a
  shim, never a change here.
* Good, because a version skew between a register, a binary and its installed stubs is named with
  its fix instead of surfacing as a confusing lint or a dead `guide` pointer.
* Bad, because the output lines and exit codes are now a contract: changing them breaks every shim,
  so a change needs a new schema version and a successor entry.
* Bad, because `doctor` deliberately stops short of the graph, so a clean doctor does not mean a
  clean lint.
