---
name: decide
description: Record a placement, naming, seam, policy, or human ruling that has already been decided, with collision-safe identity, governed surfaces, honest authorship, correct edges, an optional minted decision bead, and first-write validation.
---

# Record a decision

Use this write path immediately after a placement, naming, seam, policy, or
human ruling has been decided. Record autonomous calls, human rulings, and joint
decisions alike; authorship belongs in `decision-makers`, not in whether a
record exists.

This skill records a decision. It does not reopen the choice or perform a
docket force change. Complete the sequence in one turn, and do not create the
entry file until Steps 1 through 4 are complete.

## Record in this order

### 1. Derive governed surfaces from facts

From the repository root, collect the current tracked and untracked paths before
creating the decision entry:

```sh
{ git diff --name-only --relative HEAD; git ls-files --others --exclude-standard; } | sort -u
```

If the call was made in the current commit rather than the working tree, inspect
its actual paths instead:

```sh
git diff-tree --no-commit-id --name-only -r HEAD
```

Treat this output as evidence, not as an automatic list. Keep only paths the
decision governs:

- Use an exact path when the ruling governs one file.
- Use the narrowest directory glob, such as `lib/src/router/**`, only when the
  ruling governs present and future files under that existing directory.
- For a deleted path, name the surviving governed parent path or glob that
  still resolves.
- Exclude unrelated dirty files and the new decision entry itself unless the
  decision is about the register.
- Every `register.surfaces` item must match at least one filesystem path when
  lint runs. Never invent a broad catch-all surface.

### 2. Choose and reserve the slug before any write

Choose a short declarative slug, at most 80 characters, matching
`^[a-z0-9]+(-[a-z0-9]+)*$`. Run these checks before minting a bead or creating
a file:

```sh
decision_slug='chosen-kebab-slug'
decision_date="$(date +%F)"
decision_file="docs/decisions/${decision_date}-${decision_slug}.md"

test -d docs/decisions
printf '%s\n' "$decision_slug" | awk 'length($0) <= 80 && $0 ~ /^[a-z0-9]+(-[a-z0-9]+)*$/ { valid=1 } END { exit !valid }'
if rg -n --max-depth 1 --glob '*.md' "^[[:space:]]*slug:[[:space:]]*${decision_slug}[[:space:]]*$" docs/decisions ||
   test -e "$decision_file"; then
  printf 'slug collision: %s\n' "$decision_slug" >&2
  exit 1
fi
```

If this reports a collision, stop before minting a bead or writing a file. Read
the existing entry and cite it when it is the same decision. Choose a different
slug only when the new decision is substantively different.

### 3. Record authorship and edge meaning honestly

List the people and agent seats that actually made the call in
`decision-makers`. A human ruling names the human, an autonomous call names the agent seat, and a joint call names both. Put only people who supplied input
in `consulted`, and only actual notification audiences in `informed`; use an
empty list rather than invented participants.

Read every entry considered for an authored edge, then apply this table:

| Field | Use |
|---|---|
| `obsoletes` | The new entry replaces the named decision entirely. Read only the new entry. |
| `updates` | The new entry substantively amends the named decision, which remains in force. Read both. |
| neither | The prior entry was merely cited, influenced the call, or remains unchanged. |

Use a local slug or `repo#slug` reference. Do not infer an edge to make the
graph look complete. New entries start with cached `obsoleted-by: null`,
`updated-by: []`, and `status: accepted`; never hand-write a cached back-edge or use `proposed`.

If no options were genuinely weighed, do not add a `## Considered Options` section. If options were genuinely weighed, list only
those real options without manufacturing a table or rejected alternative.

### 4. Mint the tracker identity before citing it

Detect the tracker from the repository root. Beads is present only when both the
binary and the repository workspace resolve:

```sh
decision_bead='null'
if command -v bd >/dev/null 2>&1 && bd where --json >/dev/null 2>&1; then
  decision_title='declarative decision title'
  decision_context='why this decision was required'
  decision_bead="$(bd create "$decision_title" --type decision --description "Decision ${decision_slug}: ${decision_context}" --silent)"
  bd show "$decision_bead" --json
fi
```

When the tracker resolves, inspect `bd show` and confirm that the emitted id
exists and its `issue_type` is `decision`. If creation or verification
fails, stop before writing the entry. Never guess or preallocate an id.

When either capability check fails, keep `decision_bead='null'`. Do not install, initialize, or assume Beads. The slug remains the complete conformant identity.

### 5. Write one entry

Render every brace below with the facts already gathered, repeat list items
where required, and only then create
`docs/decisions/{YYYY-MM-DD}-{chosen-slug}.md`. When a tracker resolved,
`register.bead` receives the exact id emitted and verified in Step 4; otherwise
it is YAML `null`.

```yaml
---
status: accepted
date: {YYYY-MM-DD}
decision-makers:
  - "{actual decision-maker}"
consulted: []
informed: []
register:
  spec: 1
  slug: {chosen-slug}
  surfaces:
    - "{governed path or glob}"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: {minted decision bead id or null}
  legacy-id: null
---

# {short declarative title}

## Context and Problem Statement

{What forced the decision and what constrained it.}

## Decision Outcome

{What was decided, stated so a reader can comply without reading further.}

### Consequences

* Good, because {an actual benefit}.
* Bad, because {an actual cost or trade-off}.
```

The default body deliberately has no `Considered Options` heading. Insert that
section between context and outcome only when Step 3 identified options that
were genuinely weighed. Add `### Confirmation` only when there is a concrete
check worth recording.

### 6. Validate before reporting completion

Where the composed decisions CLI is available, run this exact command from the
repository root:

```sh
decisions lint docs/decisions --repo-root .
```

Require exit code 0 and a clean result. If it fails, correct the new entry and
run the same command again; do not weaken surfaces or authored facts to silence
a diagnostic.

Where the repository has no decisions CLI, do not install or assume tooling.
Check the file against the local `SPEC.md`, `schema/decision.schema.json`, or
`templates/decision.md` when present: filename and slug agree, the slug is
unique, every surface resolves, authored references are real, cached back-edges
have their birth values, the status is `accepted`, and the body contains no
invented section. A later lint run must pass without editing the entry.

Report the file path, its `repo#slug` identity, the verified decision bead id
or trackerless status, the governed surfaces, and the lint result.
