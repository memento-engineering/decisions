---
status: accepted
date: 2026-10-25
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "each-release-prints-and-smoke-tests-its-gas-city-pin"
  surfaces:
    - ".github/workflows/release.yaml"
    - "gc_pack/e2e.sh"
  obsoletes: []
  updates:
    - "the-decisions-cli-ships-as-prebuilt-binaries"
  obsoleted-by: null
  updated-by: []
  bead: "dec-p7f.7.5"
  legacy-id: null
---

# Each release prints its Gas City pin and smoke-tests it, and a red run is fixed forward

## Context and Problem Statement

`the-register-ships-to-gas-city-as-a-pack-of-guide-stubs` pins the pack by `sha:` of the commit a
`decisions-v` tag points at, from a `/tree/main` source. Adopters had to work out that commit
themselves, and an annotated tag's own object id is not a commit, so the obvious `git ls-remote`
answer fails gc's cache check. Nothing tested the tree-URL source with a `sha:` pin either: the
`gc_pack` CI job imports the pack from a local checkout, so the line adopters copy had never been
run.

`the-decisions-cli-ships-as-prebuilt-binaries` sets the rules for the release workflow: tags come
only from the gated release command
(`memento-engineering#releases-publish-only-through-the-gated-release-command`), prereleases stay
on GitHub, and only a stable tag reaches the tap. It says nothing about release notes, or about
checking a release once it is out.

## Decision Outcome

**Every `decisions-v` release prints its Gas City pin in its notes and then smoke-tests that pin
against GitHub. A red smoke test is fixed forward, and the tag and the release stay.**

1. **The notes print the pin.** The `release` job of `.github/workflows/release.yaml` peels the
   tag with `git rev-parse "$GITHUB_REF^{commit}"`, so an annotated and a lightweight tag give the
   same commit. It then writes a "Gas City" line with `version = "sha:<commit>"` and the pack's
   tree-URL source. One `GC_PACK_SOURCE` value feeds both the notes and the smoke test.
2. **The pin is tested the way adopters run it.** The `gc_pack_published` job runs
   `gc_pack/e2e.sh --published <tag> <sha>`, which does a rig-level import of the real GitHub
   source at that pin. It tests the release's own `linux-x64` asset, checked against `SHA256SUMS`,
   not a fresh compile. Stable releases and prereleases both run it.
3. **It blocks nothing.** The job runs after `release`. Nothing depends on it, and it changes
   nothing that has been published. The `tap` job runs beside it, under the same stable-only rule
   as before.
4. **A red run is fixed forward.** A red run means the published install line is wrong. The fix
   goes in the pack README or in a new release. Nobody moves or deletes the tag: the gated command
   is the only route to a tag, and adopters may already pin the commit it names.

### Consequences

* Good, because adopters copy a pin the release computed instead of peeling tags by hand.
* Good, because every release tests the tree-URL source with a `sha:` pin against GitHub.
* Bad, because the smoke test needs the network and GitHub's archive service, so an outage turns a
  correct release red until someone reruns the job.
* Bad, because the test runs only after the release is published. A wrong install line reaches
  adopters before anything flags it, and until the fix lands they have only the README to go on.
