# decisions

The decision-register pattern, packaged so any repo can adopt it — and memento's reference
implementation.

A register is a directory of markdown files under `docs/decisions/`, one file per decision,
modelled as **a citation graph with force** rather than a document tree. Consolidated `ADR`-style
documents are rendered views over the graph, not destinations.

The entry format is a **[MADR](https://github.com/adr/madr) 4.0 profile** — MADR's vocabulary,
sections and status values, plus a `register:` block carrying the machine-readable layer MADR
deliberately does not provide (typed supersession edges, governed surfaces, a format version).
Our files are valid MADR; MADR files are not necessarily valid here.

The format **degrades to grep**: a repo with no tooling, no Dart and no station adopts the pattern
by copying `templates/` and writing files.

| | |
|---|---|
| [`SPEC.md`](SPEC.md) | the format — front matter, force, edges, versioning, the docket |
| `schema/` | JSON Schema for entry front matter and machine-readable output |
| `templates/` | entry and rendered-view templates, and a starter `STYLE.md` |
| `skills/` | the judgement half — language-neutral markdown |
| `rubrics/` | `decision-alignment`, the committee lens |
| `docs/decisions/` | this repo's own register (self-hosted) |
| `cli/dart/` | the deterministic engine — no grid dependency |
| `grid_assets/` | the grid adapter — installs skills, vends the rubric, composes `<station> decisions` |
| `gc_pack/` | the Gas City pack — skill stubs and a doctor check over the `decisions` binary |

## Tiers

| Tier | What you get | Needs |
|---|---|---|
| 0 — prose | format, templates, a greppable register, skills as plain markdown | nothing |
| 1 — CLI | `decisions lint / index / search / new / update / obsolete / vacate / migrate-legacy`, `prime / guide / skills` for agents, `doctor`; JSON out | the [`decisions` binary](#install-the-cli), or any ecosystem impl |
| 2 — grid | overlay-installed skills, the committee lens, roster-wide cross-repo index and search, decision beads | a station |

The [Gas City pack](#install-in-gas-city) is a way to deliver tier 1 to a Gas City rig's agents,
not a tier of its own.

## Install the CLI

Every `decisions-v<version>` [release](https://github.com/memento-engineering/decisions/releases)
attaches prebuilt binaries for macOS (Apple silicon) and Linux (x64, arm64). They need no Dart
toolchain.

With Homebrew, which carries stable releases only:

```sh
brew install memento-engineering/tap/decisions
```

Or pin an exact version by download and checksum, which is what CI should do:

```sh
version=0.3.0
target=linux-x64   # or linux-arm64, macos-arm64
base="https://github.com/memento-engineering/decisions/releases/download/decisions-v$version"
curl -fsSLO "$base/decisions-$version-$target"
curl -fsSL "$base/SHA256SUMS" | grep " decisions-$version-$target\$" | sha256sum -c -
install -m 0755 "decisions-$version-$target" /usr/local/bin/decisions
```

On macOS, use `shasum -a 256 -c -` in place of `sha256sum -c -`. Prereleases (`0.3.0-rc.1`) are
downloaded the same way.

`decisions --version` names the version and the spec range the binary reads and writes:

```text
decisions 0.3.0 (reads spec <= 1, writes spec 1)
```

Exit codes are `0` for success, `1` for lint findings or a refused mutation, and `64` for a
malformed invocation. `decisions lint docs/decisions` is therefore a CI gate on its own.

Elsewhere — Intel Macs, Windows — run the same engine with the Dart SDK:

```sh
dart pub global activate --source git https://github.com/memento-engineering/decisions \
  --git-path cli/dart/decisions --git-ref decisions-v0.3.0
```

## Install in Gas City

A Gas City rig gets the `decide` and `ratify` skills, and a `decisions:binary` doctor check, by
importing the pack at [`gc_pack/decisions/`](gc_pack/decisions). Install the binary first; the
pack never installs it. [`gc_pack/decisions/README.md`](gc_pack/decisions/README.md) is the
install page: pinning, rig and city imports, upgrading, and the doctor check.

## Teach your agent the register

The binary carries the `decide` and `ratify` skills, so the instructions an agent follows always
match the engine that lints its work. These verbs arrive in the release after 0.3.0; a 0.3.0
binary rejects them as unknown commands. One line in `AGENTS.md` (or `CLAUDE.md`) is enough:

```markdown
This repo keeps a decision register in `docs/decisions/`: run `decisions prime` before deciding or changing anything.
```

- `decisions prime` — a short orientation: the register, whether it has a `STYLE.md`, each verb
  and when to reach for it.
- `decisions guide [topic]` — lists the guides, or prints one (`decide`, `ratify`) followed by
  the register's `STYLE.md` when it has one.
- `decisions skills install <dir>` — optional, for agents that load skills from a directory:
  writes `<dir>/<name>/SKILL.md` stubs that run `decisions guide <name>`. Rerunning overwrites
  earlier stubs and refuses to touch any other file. In a Gas City rig, import the
  [pack](#install-in-gas-city) instead:

  ```sh
  decisions skills install .claude/skills
  ```

For your register's prose style, copy [`templates/STYLE.md`](templates/STYLE.md) to
`docs/decisions/STYLE.md` and edit it. It covers voice, titles and length, never the format; the
engine does not read it as an entry ([`SPEC.md`](SPEC.md#register-documents-and-the-style-guide)).

## Search for precedent

Ask what already governs the work before acting. The bare tier searches the local register without
a station:

```sh
decisions search publish prerelease
# or, when composed by lunar
lunar decisions search publish prerelease
```

The grid tier runs the same reader over every mounted register in the fresh roster:

```sh
<station> decisions search publish prerelease
```

Search splits the query on whitespace and matches when **any** term is a case-insensitive
substring of a decision's title, slug or body, in that field precedence. Results are deliberately
unranked and sort by register then slug, so the same union produces the same citation order. A
migrated entry without a level-one ATX title remains searchable by slug and body.

Filters narrow the lexical matches. Repeat a filter for alternatives within that category;
different categories intersect:

```sh
decisions search --status accepted --decision-maker nico \
  --date-from 2026-09-01 --date-through 2026-09-30 \
  --slug prerelease-rungs-are-dev-beta-rc-and-rc-is-human-only \
  --surface memento-engineering/engineering.memento/power_station/AGENTS.md \
  --updates agents-publish-prereleases-humans-promote-to-stable publish prerelease
```

The repeatable filters are `--status`, `--decision-maker`, `--slug`, `--surface`, `--obsoletes`,
`--updates`, `--obsoleted-by` and `--updated-by`; the two date bounds are single and inclusive.
Slugs and edge references compare exactly, decision-maker names compare case-insensitively and
exactly, and `--surface` takes a roster-qualified path matched against the authored surface globs.
Status selectors are ergonomic aliases over the unchanged MADR values:

| `--status` | raw hit `status` |
|---|---|
| `accepted` | `accepted` |
| `obsoleted` | `superseded by <slug>` |
| `vacated` | `deprecated` |
| `rejected` | `rejected` |

Add `--json` for newline-delimited JSON: one schema-1 hit object per line, with exactly `spec`,
`slug`, `register`, `path`, `status`, `date`, `field` and `snippet`. There is no wrapper and never
an all-register dump. Snippets contain one matching line and are at most 160 characters, counting
leading and trailing ellipses. Parse diagnostics go to standard error, so incomplete coverage is
not mistaken for a clean zero-hit result.

## Record a decision

`decisions new` writes one entry and does every mechanical step for you: it checks the slug's
shape and that no entry already holds it, requires the body's `Context and Problem Statement` and
`Decision Outcome` sections, writes the birth values (`accepted`, empty caches), quotes the front
matter, and lints the register with the new entry in it before writing anything. A refusal exits
`1` and leaves the register untouched.

```sh
decisions new agents-never-watch-files \
  --title 'Agents never watch files' \
  --surface 'lib/src/watch/**' --decision-maker nico --decision-maker agent \
  --updates no-file-watching --body body.md      # or --body - to read stdin
```

It prints the written path, the entry's `<repo>#<slug>` handle, and one `next:` line per authored
edge naming the force verb that writes the target's cache — `decisions update no-file-watching
--by agents-never-watch-files` — because publishing a successor and changing its predecessor are
separate acts. What to record, which surfaces it governs and who decided stay with you; the
`decide` skill covers that judgement.

## What is ours

Borrowed deliberately: MADR's vocabulary, sections, path and status values (MIT/CC0); the IETF's
`Obsoletes`/`Updates` distinction.

Ours, because nothing in the ecosystem does it — **binding-on-write with a docket** (every ADR tool
assumes proposed → review → accepted), **cross-repo union over a live roster**, and **decisions
linked to the work graph**.

## Status

The format is settled at spec 1 and self-hosted in [`docs/decisions/`](docs/decisions).

All three tiers are built. Tier 0 works today by copying `templates/`. Tier 1 is the Dart engine
in [`cli/dart/decisions/`](cli/dart/decisions): `lint`, `index`, `search`, `new`, `update`,
`obsolete`, `vacate` and `migrate-legacy` work the register; `prime`, `guide` and `skills` teach an
agent to use it; `doctor` checks that the binary can work this register. Tier 2 is
[`grid_assets/decisions_grid_assets/`](grid_assets/decisions_grid_assets), which installs the
`decide` and `ratify` skills, vends the `decision-alignment` rubric, and composes a
`<station> decisions` command over a live roster.

Tier 1 also ships as [prebuilt binaries](#install-the-cli). Neither Dart package is published to
pub.dev yet (`publish_to: none`); consume them by git ref, or vendor `cli/dart/decisions` directly.
A tier-1 implementation in another ecosystem is unbuilt — the format is specified so that it does
not have to be Dart.
