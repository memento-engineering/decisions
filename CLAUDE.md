# decisions — the register pattern, and memento's reference implementation

**This repo is PUBLIC.** Adopters clone it to get the format. Keep that in view for every
line you write here: see *Maintainer docs vs. user docs* below.

The product is a **format** — `docs/decisions/`, one markdown file per decision, modelled as a
citation graph with force. Two Dart packages make it mechanical, and neither is required to make
it readable. `SPEC.md` is the normative text; when the code and `SPEC.md` disagree, that is a bug
in one of them, never a difference of opinion.

## Maintainer docs vs. user docs

This file and `AGENTS.md` are **maintainer docs**: how to work *on* this repo. `README.md`,
`SPEC.md`, `templates/` and `schema/` are **user docs**: how to adopt and use the pattern.

Never leak one into the other. An adopter does not care that the extension copies are
test-pinned, and a maintainer does not need the tier table re-explained. This split is an org
decision — `memento-engineering#maintainer-and-user-docs-are-separate` — not a local style
preference.

## Layout, and which copy is the source

| path | what it is |
|---|---|
| `SPEC.md` | the normative format — front matter, force, edges, versioning, the docket |
| `schema/` | JSON Schema for entry front matter and the index/lint results |
| `templates/` | entry + rendered-view templates (tier 0 adopts by copying these) |
| `skills/` | **canonical** skill sources — `decide` (write path), `ratify` (docket) |
| `rubrics/` | **canonical** rubric source — `decision-alignment`, the committee lens |
| `docs/decisions/` | this repo's own register — self-hosted |
| `cli/dart/decisions/` | the deterministic engine; no grid dependency |
| `grid_assets/decisions_grid_assets/` | the tier-2 grid adapter |

Three surfaces are **copies or generated output**. Editing the copy is always wrong — the tests
that pin them will fail, and `assets install` reverts them:

- `grid_assets/.../extension/station_overlay/claude/skills/**` mirrors `skills/**` byte for byte
  (`decide_skill_test.dart`, `ratify_skill_test.dart`, `asset_pack_test.dart`).
- `grid_assets/.../extension/rubrics/decision-alignment.md` mirrors `rubrics/`.
- `grid_assets/.../lib/src/assets/grid_asset_pack.dart` is generated from the `grid:` block of
  `grid_assets/decisions_grid_assets/pubspec.yaml`. Regenerate with
  `dart run tool/generate_grid_assets.dart`; CI checks it with `--check`.

## Build & test

Two independently resolved packages, **no workspace** — resolve and gate each one on its own.
Both are consumed by other repos through git tags, so a red package reaches consumers the moment
a tag is pushed. This is the gate that stops that:

```bash
cd cli/dart/decisions            && dart pub get && dart analyze && dart test
cd grid_assets/decisions_grid_assets && dart pub get && dart analyze && dart test
dart format --output=none --set-exit-if-changed .   # in each package
```

Lint this repo's own register — it is self-hosted, so this is a real check, not a demo:

```bash
dart run lunar:lunar decisions lint docs/decisions --repo-root .
```

## Conventions that actually bite

- **Binding-on-write.** Entries are born `status: accepted`. This profile never uses `proposed`.
  If you catch yourself writing a "pending ratification" entry, you have the model wrong.
- **A format change is itself an entry.** The register is self-hosted. Changing `SPEC.md`,
  the schema, or the templates means writing a `docs/decisions/` entry in the same change —
  and if it amends an accepted entry, an `updates:` edge rather than an edit to that entry's body.
- **The body is immutable; the force block is a cache.** `status`, `obsoleted-by` and `updated-by`
  are written by tooling from the graph. Never hand-write a cached back-edge.
- **Omit a section rather than invent content for it.** No manufactured `## Considered Options`
  table. The body template is MADR's `bare-minimal`, deliberately.
- **The format must degrade to grep.** Before adding anything the CLI must parse, ask whether a
  repo with no Dart and no station can still read the register. If not, it does not go in the
  format — it goes in the tooling.
- **Surfaces must resolve from this checkout.** `decisions lint` fails an entry whose `surfaces`
  match nothing. A decision that governs *other* repos belongs in the org register
  (`memento-engineering`), not here — that is what
  `memento-engineering#org-decisions-live-in-the-org-register` settled.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->
