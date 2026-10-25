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
  slug: "the-register-ships-to-gas-city-as-a-pack-of-guide-stubs"
  surfaces:
    - "gc_pack/**"
    - "cli/dart/decisions/test/gc_pack_test.dart"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-iiq"
  legacy-id: null
---

# The register ships to Gas City as a pack of guide stubs

## Context and Problem Statement

A Gas City rig's agents load skills from the packs the city or the rig imports. The register had
no pack, so an operator who wanted `decide` and `ratify` in a gc rig had to commit stubs into
each rig by hand, and nothing told `gc doctor` whether the `decisions` binary those stubs call was
installed at all.

`the-decisions-binary-carries-its-own-agent-instructions` already makes the binary the one source
of the skills, with `decisions skills install` writing stubs that defer to `decisions guide`.
`the-decisions-cli-ships-as-prebuilt-binaries` fixes how the binary is installed, and
`decisions-doctor-answers-whether-this-binary-can-work-this-register` gives any harness a health
check to shim over. On 2026-10-24 nico asked for a pack targeting stable gc v1.5.1 and ruled that
gc's own pack spec and guides at that release are the authority, with lenny's `gc_pack/leonard`
only a cross-check; that every pack script is a thin shim that execs the binary, with no register
logic in shell; that the binary knows nothing about Gas City, so the pack is the only adapter; and
that there is no `SessionStart` hook.

## Decision Outcome

**The register ships to Gas City as a schema-2 pack of generated guide stubs and one doctor shim,
at `gc_pack/decisions/`, and the pack carries no instruction text of its own.**

1. **Placement.** The pack root is `gc_pack/decisions/`. At v1.5.1 `gc import add` takes the
   default binding from the source's last path segment, so the skills land as `decisions.decide`
   and `decisions.ratify` without anyone passing `--name`.
2. **Skills are generated.** `gc_pack/decisions/skills/` is `decisions skills install` output,
   pinned byte for byte, with the same file set, by `cli/dart/decisions/test/gc_pack_test.dart`.
3. **One doctor check, `decisions:binary`.** `doctor/binary/run.sh` finds `decisions` on `PATH`,
   runs `decisions doctor --no-register --skills <pack>/skills`, relays its stdout and passes
   exit 0, 1 or 2 through. A missing binary, or any other exit (a binary that predates `doctor`
   exits 64), is a failure with an install hint. Compatibility is whether this binary can serve
   these stubs, never version arithmetic. The check never inspects a register: gc runs pack checks
   once per city from the pack's own directory, so per-rig register health stays with each rig's
   own `decisions lint`.
4. **Deliberately absent.** No commands: at v1.5.1 they are exposed only for city-level imports
   and run from the city root, so `gc decisions lint` would lint the wrong directory. No overlay:
   an `AGENTS.md` or `CLAUDE.md` overlay would clobber the rig's own, and a `SessionStart` hook is
   ruled out (nico, 2026-10-24). No rubric: gc has no committee surface. No pack `version` or
   `requires_gc`: the first is metadata only and v1.5.1 never reads the second. No orders in this
   version, and this entry does not rule on them: whether the pack should ship a rig-scoped
   register-health order awaits nico's ruling. A spike found that such an order is quiet when it
   fails and records an ephemeral tracking wisp on every run.
5. **It never installs the binary.** There is no `fix.sh`, so `gc doctor --fix` never mutates a
   toolchain.
6. **Imports are rig-level by default, pinned by `sha:`** of the commit a `decisions-v` tag points
   at, with a `/tree/main` source. gc's semver resolver ignores prefixed tags. A city-level import
   reaches the mayor and every rig, so the pack README asks for one level per rig.
7. **Tested against gc 1.5.1.** That is not an enforced floor, because nothing in gc enforces one.

The format is untouched: nothing in the CLI parses the pack, and the register stays readable
without gc, the pack or the binary.

### Consequences

* Good, because a rig gets both skills and a health check from one import, and the stubs cannot
  drift from the binary that prints their guides.
* Good, because a new gc release or a new harness costs a change to this pack only, never to the
  binary.
* Bad, because a skill description change now means regenerating the pack stubs as well as
  `guides.g.dart`, and once it ships, `decisions:binary` warns in every rig whose binary and pin
  come from different sides of it until the operator moves one of them.
* Bad, because while the pack has no order, nothing in gc checks a rig's register; that is left
  to each rig's CI.
