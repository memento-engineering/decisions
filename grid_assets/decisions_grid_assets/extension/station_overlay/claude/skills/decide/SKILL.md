---
name: decide
description: Use right after a placement, naming, seam, policy or human ruling has been decided, by an agent or a human, to record it in the decision register - choose the narrowest governed surfaces, honest authorship and the right edge, then write the entry with decisions new. Not for changing an existing decision's force; that is the ratify skill.
---

# Record a decision

Record a decision the moment it is made: an autonomous call, a human ruling or
a joint one. Recording does not reopen the choice. `decisions new` owns the
mechanics (slug shape and collisions, birth values, the body floor, first-write
lint); this guide is the judgement it cannot check. Run every command here
from the repository root: the path listing is relative to the working
directory, and `decisions new` writes to `docs/decisions` under it.

## When an entry is warranted

Record a placement, naming, seam, policy or human ruling that later work must
comply with; a choice that binds nothing beyond the change in hand needs none.
Run `decisions search <terms>` first, and when the register already holds the
decision, cite it as `repo#slug` instead of recording it twice.

## Surfaces: the narrowest that govern

Take the touched paths as evidence, not as the answer:
`{ git diff --name-only --relative HEAD; git ls-files --others --exclude-standard; } | sort -u`
(or `git diff-tree --no-commit-id --name-only -r HEAD` for a committed call).
Use an exact path when the decision governs one file, and the narrowest existing
directory glob (`lib/src/router/**`) only when it governs present and future
files there; never a catch-all. For a deleted path, name the surviving parent.
Leave out unrelated files, and the entry itself unless the decision is about the
register. Every surface must resolve in this checkout.

## Authorship, honestly

`--decision-maker` names whoever actually made the call: a human ruling names
the human, an autonomous call the agent seat, a joint call both. `--consulted`
is only who gave input, `--informed` only who was told; omit rather than invent.

## Edges

Read every entry you consider for an edge, then pick one meaning:

| Flag | Use |
|---|---|
| `--obsoletes` | The new entry replaces the named decision entirely. |
| `--updates` | The new entry amends the named decision, which stays in force. |
| neither | The prior entry was only cited, influenced the call, or is unchanged. |

Do not add an edge to make the graph look complete.

## Prose

The title is declarative: it states the decision, not the topic. The body has
`## Context and Problem Statement`, `## Decision Outcome` and `### Consequences`
(`* Good, because ...`, `* Bad, because ...`). Add `## Considered Options` only
when options were genuinely weighed, and `### Confirmation` only for a concrete
check: omit a section rather than invent content for it. Cite related decisions
as `repo#slug`. When the register has a `STYLE.md`, follow it:
`decisions guide decide` prints it below this guide. It governs the body, never
the front matter.

## Decision bead, only where beads resolves

When `command -v bd && bd where --json` succeeds, mint before citing:
`bd create "<title>" --type decision --silent`, confirm it with
`bd show <id> --json`, and pass `--bead <id>`. Otherwise omit `--bead`; the slug alone is a
conformant identity. Never install beads or guess an id.

## Write, then finish the edges

```sh
decisions new <slug> --title "<title>" --body body.md \
  --surface <path> --decision-maker <name> [--updates <slug>] [--bead <id>]
```

`--body -` reads stdin; `decisions new --help` has the rest. A refusal writes
nothing: fix what it names, never weaken surfaces or authored facts to silence
it. On success, run every printed `next:` line exactly as printed; it writes the
cached back-edge for the edge you authored. Never hand-write `status`,
`obsoleted-by` or `updated-by`, and run no other force verb unless the
decision-maker ruled that force change (that is `ratify`). Finish with
`decisions lint docs/decisions --repo-root .` and report the path, the
`repo#slug` handle, the bead or trackerless status, and the surfaces.

## Without the decisions binary

Install it (`brew install memento-engineering/tap/decisions`, or a pinned
release download from github.com/memento-engineering/decisions/releases), or
write the entry by hand from that repository's `templates/decision.md` and
`SPEC.md`: `docs/decisions/YYYY-MM-DD-<slug>.md`, `status: accepted`, cached
fields at birth values (`obsoleted-by: null`, `updated-by: []`), never `proposed`.
