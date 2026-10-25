---
status: accepted
date: 2026-10-25
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "every-verb-prints-refusals-and-errors-on-stderr-and-results-on-stdout"
  surfaces:
    - "cli/dart/decisions/lib/src/command.dart"
    - "cli/dart/decisions/lib/src/*_command.dart"
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-p6z"
  legacy-id: null
---

# Every verb prints refusals and errors on stderr and results on stdout

## Context and Problem Statement

`decisions new` wrote its refusals to standard error, while `decisions obsolete`, `update` and
`vacate` wrote theirs — a missing target, a missing successor, every
`DecisionMutationException` — to standard output, next to the `<verb> <slug>: clean` line a
success prints. The exit code already told a script whether a force verb succeeded, but a script
that captured standard output to relay or parse it got the refusal text mixed in, and one that
captured standard error to report a failure got nothing. Two verbs that share one wiring
(`_verbs` in `cli/dart/decisions/lib/src/command.dart`) disagreed about the same contract.

No entry stated either behaviour as a rule: `decisions-new-owns-the-write-mechanics` fixes what
`new` refuses and prints, not which stream carries it, and `SPEC.md` names exit codes only. The
force verbs' `--help` said nothing about either, and printed through the base `Command`'s
`print` rather than the injected sink. A verb's `--help` carries its own contract
(`memento-engineering#a-station-explains-itself-through-prime-and-bounded-help`), so the stream
belongs there too.

## Decision Outcome

**Every `decisions` verb writes its result to standard output and its refusals, errors and usage
errors to standard error. Exit codes do not change: `0`, `1` for a refusal, and `64` for a usage
error.**

1. **A result is what the verb was asked for.** The force verbs' `<verb> <slug>: clean`, the
   path and `next:` lines of `new`, lint's findings, doctor's findings, index and search output
   and their `--json` forms all go to standard output. Lint and doctor findings are their verb's
   result even when they exit non-zero, so they stay there. Help the caller asks for — `--help`
   or `decisions help <verb>` — is a result too: it goes to standard output and exits `0`. Only a
   usage error (an unknown option, or a missing input to a verb that treats one as a usage
   error) prints its usage on standard error, with exit `64`.
2. **A refusal is not a result.** `obsolete`, `update` and `vacate` write `error: <reason>` to
   the error sink for every refused mutation, as `new` does for its refusals. They also count a
   missing target slug or a missing successor as a refusal: `error: <reason>` on standard error
   with exit `1`, which is what they exited before this change. `new` and `lint` treat a
   missing required input as a usage error instead (exit `64`, per
   `decisions-new-owns-the-write-mechanics`). This entry moves streams, not exit codes, so that
   difference stays. They have no `--json` mode and no result schema, so no JSON consumer reads
   a refusal object from standard output; none is introduced.
3. **The help says so.** Each force verb's `--help` keeps its one-line summary for
   `decisions help` and adds its contract: exit 0 with `"<verb> <slug>: clean"` on stdout, exit
   1 with nothing written and the reason on stderr. It prints through the command's output sink,
   as `new` does. `README.md` states the stream rule beside the exit codes.

The grid adapter composes the same `_verbs` list as `<station> decisions` and only passes its
sinks through, so a station gets the change with no adapter code.

### Consequences

* Good, because a script can relay or parse standard output from any verb without filtering
  refusal lines out of it, and read the reason for a non-zero exit from one place.
* Good, because the force verbs' `--help` now states the contract a caller relies on.
* Bad, because a caller that grepped standard output for `error:` after a force verb now finds
  nothing there and must read standard error or, better, the exit code.
