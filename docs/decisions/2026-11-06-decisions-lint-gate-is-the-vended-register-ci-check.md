---
status: accepted
date: 2026-11-06
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "decisions-lint-gate-is-the-vended-register-ci-check"
  surfaces:
    - "cli/dart/decisions/lib/src/lint.dart"
    - "cli/dart/decisions/lib/src/command.dart"
    - ".github/actions/lint-gate/action.yml"
    - ".github/workflows/release.yaml"
    - "gc_pack/decisions/README.md"
  obsoletes: []
  updates:
    - "the-decisions-cli-ships-as-prebuilt-binaries"
    - "the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-each-rigs-ci"
  obsoleted-by: null
  updated-by:
    - a-surface-must-resolve-only-on-an-entry-in-force
  bead: "dec-6x7"
  legacy-id: null
---

# decisions lint --gate is the vended register CI check, run from a released binary

## Context and Problem Statement

Nine roster repositories carry a decision register. On 2026-09-13, one of them checked it in CI:
`memento-engineering`, through a hand-written `tool/lint_register.dart`. That file runs this
engine's lint, then drops one diagnostic class before deciding its exit code. Eight run no check,
and a register nothing checks rots unseen. The dropped class is an unmatched surface marked
`roster:`, which governs other repositories and resolves only at tier 2, per
`memento-engineering#org-decisions-live-in-the-org-register`. Copying that file into eight more
repositories would make eight more copies of the rule to drift.

Plain `decisions lint` cannot take the exemption silently.
`the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-each-rigs-ci` tells every rig to
run it in CI, and changing what that command means would change every rig's verdict without a
change in any rig. `the-decisions-cli-ships-as-prebuilt-binaries` already gives a repository
without Dart a checksummed binary; what is missing is a CI step that uses it.

## Considered Options

* **Exempt by default in plain `decisions lint`**, or **an opt-in gate flag on the lint verb**.
* **A job for adopters to copy**, or **one composite action this repository vends**, which
  adopters pin by release tag.
* **Prove the action in `ci.yaml`** against the latest release, or **in a post-release job**
  against the release just published.

## Decision Outcome

**The register CI check is `decisions lint --gate`: the lint verb in an opt-in mode that exempts
unmatched roster-wide surfaces and nothing else. Adopters run it from a released,
checksum-verified binary through the one action this repository vends.**

1. **An opt-in mode of the lint verb.** Plain `decisions lint` keeps its meaning, output and exit
   codes. Changing the default is rejected because it would change a documented command under
   every rig that runs it.
2. **Exactly one exempt class.** Under the gate, an unmatched surface marked `roster:` is exempt,
   judged by the shared predicate the force verbs and `decisions new` already apply. Every other
   finding is fatal, an unmatched repo-local surface included. Widening the exemption takes a new
   entry.
3. **Lint's contract, unchanged.** What the gate does not exempt is still lint's result: the same
   stream, the same line form and the same JSON schema. A run exits 0 when nothing remains and 1
   otherwise, and a usage error stays a usage error. A missing register stays a finding, as plain
   lint reports it. A clean gate says how many surfaces it exempted, so the exemption is visible
   in a CI log.
4. **One vended action, pinned by release.** Adopters call the lint-gate action from this
   repository at a release tag. It downloads that release's binary for the runner, verifies it
   against the release's checksums and runs the gate. The adopter adds no Dart toolchain and no
   script. A job to copy is rejected because every copy of the download and verify steps is one
   more place to drift, which is the failure the hand-written wrapper already shows.
5. **Proved after each release, fixed forward.** Each release runs the action against this
   repository's own register with the release just published. A pull request cannot prove it,
   because no released binary carries a flag that the pull request adds. A check in `ci.yaml`
   against the latest release is rejected: it would fail until the next release, and after that
   it would test the previous release rather than the change. A red run is fixed forward, as
   `each-release-prints-and-smoke-tests-its-gas-city-pin` rules for the Gas City pin.

This updates `the-decisions-cli-ships-as-prebuilt-binaries`, whose release gains one more
post-release job. It also updates
`the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-each-rigs-ci`, whose rig CI check
is now the gate.

This is falsified when a single checkout can resolve a roster-wide surface. The exemption then has
no reason left, and a new entry removes it.

### Consequences

* Good, because every adopter runs one copy of the exemption, so retiring `memento-engineering`'s
  wrapper is a drop-in.
* Good, because a gated repository needs one workflow job and nothing else.
* Bad, because this repository's first green run of the action arrives with the first release
  after this lands. Until then, only the tests and a local run prove it.
* Bad, because an adopter moves two values together on upgrade: the action's tag and its version
  input.
