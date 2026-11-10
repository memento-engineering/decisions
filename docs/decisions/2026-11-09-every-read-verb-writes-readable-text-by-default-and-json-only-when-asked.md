---
status: accepted
date: 2026-11-09
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "every-read-verb-writes-readable-text-by-default-and-json-only-when-asked"
  surfaces:
    - "cli/dart/decisions/lib/src/index_command.dart"
    - "cli/dart/decisions/lib/src/command.dart"
    - "SPEC.md"
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-pln"
  legacy-id: null
---

# Every read verb writes readable text by default and JSON only when asked

## Context and Problem Statement

The read verbs of one binary disagreed on who reads their output by default. `decisions lint`,
`decisions search` and `decisions doctor` wrote readable text and took an opt-in `--json`;
`decisions index` wrote JSON and took an opt-in `--human`. Nothing about indexing justified the
difference, and it was the costly one: measured at the lunar grid home on 2026-09-09, a bare
roster-wide `lunar decisions index` wrote 102803 characters of JSON for 302 decisions straight to
the terminal, where the readable summary of the same answer is 304 lines. An operator asking what
the roster has decided got a wall of JSON unless they already knew the flag existed.

On 2026-11-09 nico ruled that the CLI's output flags are one consistent API: index matches lint,
search and doctor, and `--human` is removed rather than kept as an alias. Breaking the output is
acceptable under semver.

## Decision Outcome

**A `decisions` verb that reads the register writes readable text by default and JSON only when
the caller asks, through one `--json` flag declared alike on every such verb.**

1. **The default reader is a person.** A bare read verb answers someone at a terminal; a script or
   skill that parses the answer asks for the machine form, so the cost of the flag falls on the
   caller that can carry it.
2. **One opt-in, declared alike.** A read verb's JSON flag takes lint's name, negatability and
   help, so a caller learns it once. `test/command_test.dart` pins index against lint.
3. **A retired output flag is removed, not aliased.** It becomes an unknown option, which is a
   usage error on standard error with exit `64` under
   `every-verb-prints-refusals-and-errors-on-stderr-and-results-on-stdout`.
4. **The JSON does not change.** The machine form is the same document under the same schema, so
   no format rule moves and entries stay at `register.spec: 1`, as `spec-and-artifact-versioning`
   requires.
5. **A breaking output change moves the minor version while below 1.0.** The binary that drops
   the old default is a new minor release, so a pin on the old one keeps working.

The flag lives in `cli/dart/decisions/lib/src/index_command.dart`, beside lint's in
`cli/dart/decisions/lib/src/command.dart`. `SPEC.md`'s tier table says the CLI writes readable
text out and JSON on request; that row still names a capability and no verb, so
`spec-tier-table-describes-capabilities-and-defers-the-verb-list-to-the-cli` holds unchanged.

Keeping `--human` as an alias is rejected (nico's ruling, 2026-11-09): two spellings of one
default are not one API, and an alias that does nothing teaches a caller a flag with no effect.

This is wrong if a read verb's primary caller becomes a machine that cannot pass a flag; that
takes a new entry.

## Considered Options

* Keep `--human` as an accepted alias of the new default.

### Consequences

* Good, because an operator asking what the roster has decided gets a readable answer without
  knowing a flag.
* Good, because every read verb takes the same flag with the same meaning.
* Bad, because a script or skill that read a bare `decisions index` as JSON breaks until it adds
  `--json`.
* Bad, because the ratify skill and the decision-alignment rubric now call `decisions index
  --json`, which a 0.4.0 binary refuses with exit `64`, so a station needs a 0.5.0 binary once
  those skills install.
