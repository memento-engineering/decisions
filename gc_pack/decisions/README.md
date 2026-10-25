# decisions — a Gas City pack

This pack brings the [decision register](../../README.md) to the agents of a Gas City rig. It
holds two things:

- **Skills `decide` and `ratify`.** Each is a stub that tells the agent to run
  `decisions guide <name>`, so the instructions always come from the installed `decisions`
  binary and match the engine that lints the agent's work. gc links them into each agent's skill
  directory as `decisions.decide` and `decisions.ratify`.
- **A doctor check, `decisions:binary`.** It reports whether `decisions` is on `PATH` and can
  serve this pack's skills, by running `decisions doctor --no-register --skills <pack>/skills`.

The pack carries no instructions of its own, and it never installs the binary. It has no
commands, overlay, formulas or orders.

Tested against **gc 1.5.1**. Notes marked *v1.5.1* describe that release and may change in the
next one.

## 1. Install the binary first

Every skill in this pack runs `decisions`, so install it before importing the pack, from the
release you will pin the pack to:

```sh
brew install memento-engineering/tap/decisions
```

or by a pinned, checksummed download (see [Install the CLI](../../README.md#install-the-cli)).
Use the prebuilt binary rather than `dart pub global activate`: gc gives each doctor check a few
seconds at `gc start`, and a snapshot is slower to start.

Install it where the sessions gc launches will find it, not only on your own shell's `PATH`.

## 2. Pin a release

Releases are tagged `decisions-vX.Y.Z`. gc's semver resolver does not read prefixed tags, so pin
the pack by the commit a tag points at, with `sha:`.

The release notes print that pin as a ready `version = "sha:<commit>"` line, beside the source
to use. Take it from the release your binary came from:

```sh
src=https://github.com/memento-engineering/decisions/tree/main/gc_pack/decisions
sha=<commit>   # from the release notes' "Gas City" line
```

A release with no "Gas City" line was cut before the notes printed it. Peel its tag as below,
and check that the commit carries `gc_pack/decisions` before you pin it: releases older than the
pack do not. To resolve a tag's commit yourself, peel the tag, because an annotated tag's own
object id is not a commit:

```sh
tag=decisions-vX.Y.Z   # the release your binary came from
sha=$(git ls-remote https://github.com/memento-engineering/decisions \
  "refs/tags/$tag" "refs/tags/$tag^{}" | sort -k2 | tail -n1 | cut -f1)
src=https://github.com/memento-engineering/decisions/tree/main/gc_pack/decisions
```

With a `sha:` pin, `/tree/main` in the source only names where the pack lives; the commit comes
from the pin.

## 3. Import it

### Per rig (recommended)

Only that rig's agents get the skills:

```sh
gc rig add ~/src/app --name app          # if the rig is new; do not pass --include (below)
gc --rig app import add "$src" --name decisions --version "sha:$sha"
gc import check
```

`import add` writes the lock and fills the cache, so no separate `gc import install` is needed.
The same import, written by hand in `city.toml` (run `gc import install` afterwards):

```toml
[[rigs]]
name = "app"

[rigs.imports.decisions]
source = "https://github.com/memento-engineering/decisions/tree/main/gc_pack/decisions"
version = "sha:<commit>"
```

### For rigs you add later

Put the same table under `[defaults.rig.imports.decisions]` in `city.toml`. *v1.5.1:* gc copies it
into each rig added **afterwards** by a `gc rig add` **without** `--include`. It does not reach
rigs that already exist; import those per rig.

`gc rig add` copies the table but does not install it. Until you run `gc import install`, the
whole city fails to load with `remote import ... is not installed (missing packs.lock entry)`:

```sh
gc rig add ~/src/api --name api
gc import install
gc import check
```

### City-wide

A city-level import reaches the mayor **and** every rig's agents:

```sh
gc import add "$src" --name decisions --version "sha:$sha"
```

It is written to the city's root `pack.toml` as `[imports.decisions]`. Use it only where every
agent works a register: the mayor's working directory is the city root, which usually has no
`docs/decisions`.

## Rules

- **One level per rig.** A city import already reaches every rig, so adding a rig import as well
  lists each skill twice in that rig's agents.
- **One skill channel per rig.** A gc rig gets its skills from this pack; a station-managed rig
  from its overlay; anything else from `decisions skills install .claude/skills`. A rig with
  committed stubs *and* this pack sees both `decide` and `decisions.decide`.
- **One pin per city** (*v1.5.1*). gc allows a single `sha:` for this source across the whole
  city: every `[rigs.imports.*]`, `[defaults.rig.imports.*]` and `[imports.*]` table that names it
  must carry the same `version`, or `gc import install` and `gc import add` fail with
  `incompatible pinned versions`.
- **Do not use `gc rig add --include` for this pack** (*v1.5.1*). It writes the import with no
  version. If that is the source's only import, `gc import install` fails with
  `no semver tags found`, because this repo's tags are prefixed. If another import already pins
  the source, install succeeds and the unpinned import quietly follows that pin. Once that pin
  is gone, install still works from the commit left in `packs.lock`, but `gc import upgrade`,
  or an install without that lock, fails with `no semver tags found`.
- **Upgrade** by moving every `version` that names this source to the new release's commit in
  one edit, the defaults table included, then running `gc import install` and `gc import check`.
  Upgrade the binary to the same release. Moving only one import fails with
  `incompatible pinned versions`, and running `import add` again fails with
  `import "decisions" already exists`.
- **After a cache wipe** (*v1.5.1*) the whole city fails to load, not just this pack:
  `gc skill list` and `gc config show` exit 1 for every agent, the mayor included, with
  `remote import ... is locked but not cached`. The `decisions:binary` check is not registered
  then, so it cannot report the problem. Run `gc import install` to refill the cache.

## The doctor check

```sh
gc doctor --check decisions:binary
```

| result | meaning |
|---|---|
| ok | `decisions` is installed and these stubs are exactly what it would write |
| warning | the binary works but the stubs differ from it, or it carries a guide this pack lacks: move the pin or the binary so they match |
| error | `decisions` is not on `PATH` or not executable, predates `decisions doctor`, or lacks a guide a stub names |

The check runs at `gc start` too. A warning or error there is mailed to the mayor on every start
until it is fixed.

It checks the binary and the stubs, never a register. *v1.5.1:* gc runs a pack's doctor checks once
per city, from the pack's own directory, whichever level imports it, so the check has no rig to
look at. Check each rig's register in that rig's own CI:

```sh
decisions lint docs/decisions
```
