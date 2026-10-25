---
status: accepted
date: 2026-10-17
decision-makers: [nico, agent]
consulted: []
informed: []
register:
  spec: 1
  slug: the-decisions-cli-ships-as-prebuilt-binaries
  surfaces:
    - "cli/dart/decisions/bin/decisions.dart"
    - "cli/dart/decisions/tool/homebrew_formula.dart"
    - ".github/workflows/release.yaml"
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by:
    - each-release-prints-and-smoke-tests-its-gas-city-pin
  bead: dec-n8y.2
  legacy-id: null
---

# The decisions CLI ships as prebuilt binaries

## Context and Problem Statement

Tier 1 had no way in for a repo without Dart. The engine had no executable entry point, the
package is `publish_to: none`, and the repo cut no releases, so it ran only through the grid or a
hand-written wrapper. Adopters re-implemented the lint instead: one keeps a spec-1 register
checked by a private Python script, a third copy of the rules that drifts from `SPEC.md` and from
this engine unnoticed (GitHub issue #36).

Dart compiles to self-contained executables, so this is packaging, not a port. A second engine
in another language would have to track every spec change in step with this one.

## Considered Options

* **Five targets** (macOS arm64 and x64, Linux x64 and arm64, Windows x64), as the issue proposed.
* **Three targets**: macOS arm64, Linux x64, Linux arm64.
* **Formula bumps pushed by this repo's release** with a token scoped to the tap, against **the tap
  polling for releases** on a schedule with its own token. A scheduled workflow in a public repo
  is disabled after 60 days without activity, so the poller would stop silently between releases.

## Decision Outcome

**The standalone `decisions` executable is tooling, not format.** The format still degrades to
grep; a binary is one more way to run this engine, never a requirement to read a register.

1. **Entry point.** `cli/dart/decisions/bin/decisions.dart` exposes every verb at top level
   (`decisions lint`, not `decisions decisions lint`). `--version` prints the artifact version,
   the spec range it reads and the spec it writes, per `spec-and-artifact-versioning`. Exit codes:
   0 success, 1 lint findings or a refused mutation, 64 a malformed invocation.
2. **Three targets** — `macos-arm64`, `linux-x64`, `linux-arm64` — each compiled *and executed*
   on its own native runner before it is attached. Assets are raw executables named
   `decisions-<version>-<target>`, with one `SHA256SUMS` per release.
3. **Built from tags, never cutting them.** `.github/workflows/release.yaml` runs on a
   `decisions-v<version>` tag. The tag is cut only by the gated release command
   (`memento-engineering#releases-publish-only-through-the-gated-release-command`); the workflow
   refuses a binary whose `--version` disagrees with the tag.
4. **Prereleases stay on GitHub.** A version with a prerelease suffix publishes as a GitHub
   prerelease. Only a stable tag — a human promotion, per
   `memento-engineering#agents-publish-prereleases-humans-promote-to-stable` — updates the
   Homebrew formula in `memento-engineering/homebrew-tap`, under the org's tap rules
   (`memento-engineering#org-clis-ship-through-one-homebrew-tap`).
5. **The formula is generated, not maintained.** `tool/homebrew_formula.dart` renders it from the
   release's own `SHA256SUMS`, and the release workflow pushes it with the `HOMEBREW_TAP_TOKEN`
   org secret (contents write on the tap only). A release missing a target's checksum never reaches
   the tap.

### Consequences

* Good, because a repo with no Dart toolchain can pin the official engine by version and checksum
  instead of keeping its own copy of the lint rules.
* Good, because every attached binary has run `--version` and linted this register clean on its
  own platform before anyone can download it.
* Good, because Homebrew users only ever see versions a person promoted.
* Bad, because Intel Macs and Windows have no binary; those adopters still need the Dart SDK.
* Bad, because the version is a constant in `lib/src/version.dart` beside the pubspec; a test pins
  the two together, so a bump that forgets one fails CI rather than shipping.
