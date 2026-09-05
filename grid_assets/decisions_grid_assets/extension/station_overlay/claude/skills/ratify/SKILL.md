---
name: ratify
description: Hold a docket for one decision register - compute the four ratified trigger signals, present a bounded worksheet of the decisions needing a force change with a proposed disposition and its evidence, and record every ruling as an entry plus its force operation.
---

# Hold a docket

A docket is the human-agent force-change event, and the only place this pattern
asks a human for anything. Recording a decision needs no human: decisions bind
on write. Obsoleting, updating, vacating and rejecting need one.

Hold a docket for ONE register, and only when a signal has fired. The signals,
their thresholds and the per-register scope are ratified in
`decisions#docket-triggers`. Never read the whole register to hold a docket:
an unreadable register is the failure mode this event exists to design away.
Every lookup is a command whose JSON you parse; spend your own judgement only
on the argument, which decisions are actually in tension and which way.

Complete the sequence in one turn. Write no entry and run no force command
before the human has ruled on its row.

## Hold in this order

### 1. Read the two commands, never the register

From the repository root of the register under docket:

```sh
docket_register='docs/decisions'
docket_repo="$(basename "$(pwd)")"
docket_date="$(date +%F)"
docket_scratch="$(mktemp -d)"

decisions lint "$docket_register" --repo-root . --json > "$docket_scratch/lint.json"
decisions index > "$docket_scratch/index.json"
```

`decisions index` with NO positional register argument is load-bearing. Under a
station the composed command resolves the live mounted-substation roster and
returns the union, so a per-register docket still sees cross-repo citations and
unresolved edges. Without a station, pass the register directories you have:
`decisions index docs/decisions`.

Parse the JSON of both. Never scrape the prose form of either command.

* Lint carries `valid` and `diagnostics[]`, each with `ruleId`, `file` and
  `message`. A diagnostic's `file` ends in `<date>-<slug>.md`, so its slug
  needs no further lookup.
* Index carries `decisions[]`, each with `originRegister`, `originPath`,
  `slug`, `status`, `surfaces[]` and `edges[]`; each edge with `kind`,
  `reference`, `resolution` and, when resolved, `targetRegister` and
  `targetSlug`.

Only decisions whose `originRegister` is the register under docket may be RULED
on. Keep every other register as evidence: a sibling register has exactly the
same force.

Remove `$docket_scratch` before reporting. It is scratch, not state.

### 2. Find the last docket, the only per-register marker

A docket records itself as an entry whose slug is `docket-<YYYY-MM-DD>`. That
entry is the "since the last docket" marker. No other state exists, and none may
be introduced.

```sh
docket_last="$(grep -Erl --include='*.md' \
  '^[[:space:]]*slug:[[:space:]]*docket-[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' \
  "$docket_register" | sort | tail -1)"
docket_since="$([ -n "$docket_last" ] && basename "$docket_last" | cut -c1-10 || printf '')"
docket_new="$(ls "$docket_register" | awk -v since="$docket_since" \
  '/^[0-9]{4}-[0-9]{2}-[0-9]{2}-.*\.md$/ && substr($0,1,10) > since' | wc -l | tr -d ' ')"
```

An empty `docket_since` means the register has never held a docket: every entry
is new, and `docket_new` counts them all.

Hold at most one docket per register per day. The slug carries the date, so a
second same-day docket would collide on identity; carry its signals to the next
one.

### 3. Compute the four signals

| # | signal | measure | fires at | source |
|---|---|---|---|---|
| 1 | contradiction | lint diagnostics, plus decisions the `decision-alignment` lens graded F for a structural contradiction | 1, immediately | `diagnostics[]`; the citation ledger |
| 2 | pending force request | an authored `obsoletes` or `updates` edge whose target's force cache was never written | 1, immediately | `force.obsoleted-by`, `force.updated-by`, `force.status` |
| 3 | citation pressure | citations of ONE decision by `decision-alignment` since the last docket | 5 | the citation ledger |
| 4 | growth | entries dated after the last docket | 10 | `docket_new` |

A docket fires when ANY row fires. It does NOT fire on the calendar, on bead
closes, on landings, or on register size alone below the growth threshold.

The citation ledger is the caller's input: the station's record of what
`decision-alignment` cited and how it graded. Where the caller supplies none,
report signal 3 and the lens half of signal 1 as `unavailable` on the
worksheet. Never report an unmeasured signal as zero.

If no row fires, say so, hold no docket, and write nothing.

### 4. Build the worksheet

One row per decision needing a force change, and nothing else. Bound the
reading: open only entries the signals named, at most one per row, resolved by
the slug the index already returned.

```sh
grep -Erl --include='*.md' '^[[:space:]]*slug:[[:space:]]*<slug>[[:space:]]*$' '<originPath>'
```

Quote at most one sentence per entry, the first of its `## Decision Outcome`.
Never paste an entry body, and never open an entry no signal named.

| row class | signal | proposed disposition | what accepting runs |
|---|---|---|---|
| pending force request | 2 | the force operation the request already authored | the force command alone, against the already-recorded successor |
| contradiction | 1 | a new disposition entry authoring the resolving edge, then its force operation | `decide`, then the force command |
| citation pressure | 3 | affirm, unless the reading shows a real tension | nothing; the docket entry records the affirmation |
| growth | 4 | affirm, or a new disposition entry where a new entry should have carried an edge | nothing, or `decide` then the force command |

A docket NEVER edits an authored field. `obsoletes`, `updates`, `surfaces`,
`spec`, `slug`, `bead` and `legacy-id` are written by their author once; a
ruling that changes the graph records a new entry and runs a force command.

Present the worksheet as one table with exactly these columns, then STOP and
ask:

| # | decision | signal | evidence | proposed disposition | argument |

`decision` is the canonical `<repo>#<slug>`. `evidence` is the literal `ruleId`
plus `file`, or the index field, that produced the row, never a paraphrase.
`argument` is one sentence: which way the tension resolves and why.
`proposed disposition` is exactly one of `obsolete by <slug>`,
`update by <slug>`, `vacate with <slug>`, `reject` or `affirm`.

The human rules per row, `accept <n>` or `reject <n>`. There is no default and
no batch accept. A row left unruled is `deferred` and carried to the next
docket.

### 5. Apply the accepted rows in this order

Apply pending-force-request rows first, oldest request entry first; then
contradiction and new-decision rows one at a time, each entry written and its
force command run before the next row begins.

```sh
decisions obsolete <target-slug> --by <successor-slug> --register "$docket_register" --repo-root .
decisions update <target-slug> --by <successor-slug> --register "$docket_register" --repo-root .
decisions vacate <target-slug> --successor <successor-slug> --register "$docket_register" --repo-root .
```

Honour what the force commands enforce, and never work around them:

* The target must currently be `accepted`; the successor must be a distinct,
  binding entry.
* `obsolete` requires the successor be the SOLE entry authoring an `obsoletes`
  edge to the target; `update` requires the successor author an `updates` edge.
* `vacate` requires a concrete successor slug. Never `none`: record a decision
  stating that no rule governs the surface and pass its slug.

For a row whose disposition needs a NEW entry, record it with the `decide` skill
before running the force command, with the ruling human in `decision-makers` and
exactly one authored edge to the target. Between those two acts the register is
transiently dirty by exactly the target's `force.*` rules; that is why they are
one act. Do not stop at `decide`'s closing lint until the paired force command
has run.

The force commands refuse to write while the register is dirty ANYWHERE else,
reporting `candidate register is not clean: <rules>` and changing no file. That
guard is why signal 2 fires on the FIRST pending request. If a docket finds more
than one unsettled request, report the refusal verbatim together with every
outstanding request and stop; never hand-edit a force cache to get past it.

### 6. Record the docket's own entry, last, and validate

Write ONE docket entry per docket, after every accepted row has been applied,
and write it even when every row was rejected. A docket that leaves no entry
leaves no marker, and the same signals fire forever.

Record it with the `decide` skill, with these values fixed:

```yaml
---
status: accepted
date: {YYYY-MM-DD}
decision-makers:
  - "{the ruling human}"
  - "{the agent seat that held the docket}"
consulted: []
informed: []
register:
  spec: 1
  slug: docket-{YYYY-MM-DD}
  surfaces:
    - "docs/decisions/**"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: {minted decision bead id or null}
  legacy-id: null
---

# Docket {YYYY-MM-DD} for the {repo} register

## Context and Problem Statement

{Which signals fired, each with its measured value against its threshold, and
which were unavailable.}

## Decision Outcome

| row | decision | signal | disposition | ruling |
|---|---|---|---|---|
| {n} | {repo#slug} | {1-4} | {the proposed disposition} | {accepted, rejected or deferred} |

{One sentence per accepted row: the argument the human ruled on.}

### Consequences

* Good, because {what the rulings settled}.
* Bad, because {what they cost}.
```

The docket entry authors no edges; the disposition entries carry them.

Then, from the repository root:

```sh
decisions lint docs/decisions --repo-root .
```

Require exit code 0 and a clean result. If it fails, run the force command the
failing rule names; never weaken an entry or hand-write a cached back-edge to
silence a diagnostic.

Report the register, every signal with its measured value, every worksheet row
with its ruling, the docket entry's `<repo>#<slug>`, each disposition entry with
the force operation it paired with, and the lint result.
