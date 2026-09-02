---
status: accepted
date: 2026-09-02
decision-makers: [nico, governor]
consulted: []
informed: []
register:
  spec: 1
  slug: docket-triggers
  surfaces:
    - "SPEC.md"
    - "skills/**"
  obsoletes: []
  updates: [the-decision-register]
  obsoleted-by: null
  updated-by: []
  bead: dec-iut
  legacy-id: null
---

# A docket fires on signal thresholds, never on the calendar, and its scope is one register

## Context and Problem Statement

[the-decision-register](2026-08-29-the-decision-register.md) makes decisions bind on write and
moves the human's judgement to the docket: the force-change event where obsoleting, updating,
vacating and rejecting are ruled on. SPEC.md left one item OPEN: which signals trigger a docket
and at what thresholds. The evidence for calendar review is damning: the org ran exactly one
ratification round in its history, and power_station promoted nothing across 38 amendments. A
trigger that fires constantly is the same as no trigger; one that never fires is a calendar with
extra steps. The bead also left open whether a docket is per-register or roster-wide.

## Considered Options

* Calendar cadence (weekly / per release)
* Register size alone
* Signal thresholds: contradiction, pending force request, citation count, growth since the last docket
* Roster-wide dockets over the cross-register index

## Decision Outcome

**Signal thresholds, per register.** A docket for a register fires when ANY of these holds:

1. **Immediately** on a contradiction reported by `decisions lint` or by the `decision-alignment`
   lens (a spec graded against a decision that conflicts with another binding decision).
2. **Immediately** on a pending force request: an obsolete, update or vacate recorded by an agent
   seat that has not yet been ruled on.
3. When one decision has been **cited by `decision-alignment` five or more times** since the
   register's last docket. Repeated citation is the signal that a decision is load-bearing enough
   to deserve the human's eye.
4. When the register has **grown by ten entries** since its last docket.

A docket does NOT fire on the calendar, on bead closes, on landings, or on register size alone
below the growth threshold. Size without growth is history, not a signal.

**Scope is per register.** Roster-wide dockets would make every docket the whole org. The
roster-wide `decisions index` remains the worksheet's READ surface, so a per-register docket still
sees cross-repo citations and contradictions; only the set of decisions up for a ruling is scoped
to the one register that fired.

### Consequences

* The ratify skill (dec-570) computes the four signals from `decisions index` + `decisions lint`
  and the alignment lens's citation ledger, and produces the worksheet for the register that fired.
* "Since the last docket" needs a durable marker per register; the ratify skill records it as the
  docket's own entry (a docket produces entries with the human in `decision-makers`, per
  the-decision-register), so no new state is introduced.
* SPEC.md's OPEN marker is replaced by a pointer to this entry.
