---
status: accepted
date: 2026-11-09
decision-makers:
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "a-nightly-run-checks-the-gas-city-pack-against-gc-latest"
  surfaces:
    - ".github/workflows/nightly.yaml"
    - ".github/actions/gc-sandbox-tools/action.yml"
    - ".github/workflows/ci.yaml"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-p7f.7.8"
  legacy-id: null
---

# A nightly run checks the Gas City pack against gc latest

## Context and Problem Statement

CI checks the Gas City pack against exactly one gc. The `gc_pack` job runs `gc_pack/e2e.sh`
against the pinned 1.5.1, and nothing in this repository ever ran the pack against a newer gc. A
gc release that changes how packs are imported, cached or ordered therefore reached adopters,
who install whatever gc is current, before this repository saw it. The pin moved only when
someone thought to move it.

A scheduled workflow is the obvious answer, and it has its own failure: GitHub disables a public
repository's schedule after 60 days without activity, silently, so a quiet stretch would end
the check without anyone noticing.

`each-release-prints-and-smoke-tests-its-gas-city-pin` is the precedent for a check that runs
beside the gate rather than in it: its post-release job blocks nothing, and a red run is fixed
forward.

## Decision Outcome

**The pack's e2e runs every night against gc's latest release, beside the pinned CI run, which
stays the gate.**

1. **The pinned run gates; the nightly only signals.** Pull requests, merges and releases are
   judged against the pinned gc and nothing else. The nightly never blocks a landing or a
   release, and a green nightly is not a reason to move the pin by itself.
2. **A latest gc is trusted only through its own release's checksums file.** The pinned gc is
   still checked against its pinned sha256 as well. Any version that is neither the pin nor
   `latest` is refused before anything downloads, so no third gc runs with neither check.
3. **A red nightly blocks nothing and files no issue.** It is a red scheduled run in the Actions
   tab. It is fixed forward: by bumping the pin once the pack works with the new gc, or by
   fixing the pack README claim the failing scenario names.
4. **Every push to `main` re-enables the schedule.** The job that does it is the only job in CI
   granted write access to Actions, and it runs no checkout and no downloaded binary.

The rules are carried by `.github/actions/gc-sandbox-tools/action.yml`, which installs either
gc, and `.github/workflows/nightly.yaml`, which asks for the latest; the keep-alive lives in
`.github/workflows/ci.yaml`.

This decision is wrong if a gc release that breaks the pack still reaches an adopter before this
repository sees it, or if a red scheduled run goes unseen because no issue is filed.

### Consequences

* Good, because a gc release that breaks the pack shows as a red run within a day of its release.
* Good, because the keep-alive needs no human: any landing on `main` revives a lapsed schedule.
* Bad, because a red nightly is seen only by someone who looks at the Actions tab; nothing
  notifies anyone.
* Bad, because a latest tarball is trusted on its own release's checksums file alone, which
  proves the download intact but not who built it.
* Bad, because a repository with no landing for 60 days still loses the schedule until the next
  push to `main`.
