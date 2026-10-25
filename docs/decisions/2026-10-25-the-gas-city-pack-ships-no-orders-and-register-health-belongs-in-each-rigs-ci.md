---
status: accepted
date: 2026-10-25
decision-makers:
  - "nico"
consulted: []
informed: []
register:
  spec: 1
  slug: "the-gas-city-pack-ships-no-orders-and-register-health-belongs-in-each-rigs-ci"
  surfaces:
    - "gc_pack/decisions/**"
  obsoletes: []
  updates:
    - "the-register-ships-to-gas-city-as-a-pack-of-guide-stubs"
  obsoleted-by: null
  updated-by: []
  bead: "dec-kch"
  legacy-id: null
---

# The Gas City pack ships no orders; register health belongs in each rig's CI

## Context and Problem Statement

`the-register-ships-to-gas-city-as-a-pack-of-guide-stubs` left orders out of the pack's first
version without ruling on them. The open question was whether the pack should ship a rig-scoped
exec order that runs `decisions doctor` in each importing rig, since the pack's one doctor check
cannot see a rig: gc 1.5.1 runs pack doctor checks once per city, from the pack's own directory.

A spike in a gc 1.5.1 sandbox (bead `dec-p7f.7.2`) ran such an order and found three things.
A failing run is close to silent: it writes an `order.failed` event and a supervisor log line,
mails and nudges no one, shows nothing in `gc status`, and surfaces only as an advisory `gc doctor`
warning after three consecutive failures. Every run, failing or not, writes a tracking bead into
the rig's own beads store, kept seven days and never fewer than the newest ten per order, with no
per-order opt-out. And no trigger means "the register changed": gc has no commit or push event,
so the best fit is a schedule such as a daily cron.

## Decision Outcome

**The Gas City pack ships no orders. A rig's register health is checked by that rig's own CI
running `decisions lint`, not by the pack (nico's ruling, 2026-10-25).**

A CI lint fails the change that breaks the register, on the pull request that introduces it, and
blocks it. An order would find the same breakage up to a day later, tell no one, and add a bead to
every importing rig's tracker on every run. The pack README already tells rig owners to run
`decisions lint docs/decisions` in their CI; `gc_pack/decisions/` gains no `orders/` directory.

This amends the deliberately-absent list of
`the-register-ships-to-gas-city-as-a-pack-of-guide-stubs`: orders are absent by ruling, not
pending one. A later order needs its own entry that obsoletes or updates this one.

### Consequences

* Good, because register health is enforced where a failure blocks the change that caused it,
  rather than reported after the fact to an event log.
* Good, because importing the pack writes nothing into a rig's tracker.
* Bad, because a rig whose repository has no CI lint gets no register check from gc at all; the
  pack's doctor check only covers the binary and its skill stubs.
