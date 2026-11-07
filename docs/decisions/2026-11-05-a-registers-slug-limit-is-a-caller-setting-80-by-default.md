---
status: accepted
date: 2026-11-05
decision-makers:
  - "nico"
  - "agent"
consulted: []
informed: []
register:
  spec: 1
  slug: "a-registers-slug-limit-is-a-caller-setting-80-by-default"
  surfaces:
    - "SPEC.md"
    - "schema/decision.schema.json"
    - "cli/dart/decisions/lib/src/entry.dart"
    - "cli/dart/decisions/lib/src/register_union.dart"
    - "cli/dart/decisions/lib/src/record.dart"
    - "cli/dart/decisions/lib/src/command.dart"
    - "grid_assets/decisions_grid_assets/lib/src/command.dart"
  obsoletes: []
  updates:
    - "decisions-new-owns-the-write-mechanics"
  obsoleted-by: null
  updated-by: []
  bead: null
  legacy-id: null
---

# A register's slug limit is a setting its caller supplies, 80 characters by default

## Context and Problem Statement

The format capped a slug at 80 characters, and the engine applied the cap on every read as well
as on `decisions new`. A register whose slugs are longer could not be read at all: the grid's
register holds 105 entries, 26 of them with slugs over 80 characters, and every verb run over it
stopped at the first one. On 2026-11-05 nico ruled that the limit is configurable, and that each
repository's station definition supplies its register's settings to the verbs.

## Decision Outcome

**A register's slug limit is a setting its caller supplies, 80 characters by default.**

1. **The default is unchanged.** A register whose caller sets no limit admits and refuses exactly
   the slugs it did before.
2. **The setting lives with the caller, not in the register.** The station that composes the
   verbs supplies each register's limit. A command-line caller supplies one limit for every
   register a run reads, and that explicit value wins over a composed one, as an explicit roster
   wins over a composed one. No file in the register states the limit, so a register with no
   tooling still reads by grep.
3. **One limit per register, wherever it is read or written.** Within one run, every parse,
   lint, index, search, write and force change of a register applies the same limit, and so
   does the candidate lint a write or force change runs. A cross-register read applies each
   sibling register's own limit as its caller supplies it, and the default when none is supplied.
4. **Over the limit is refused or reported, never truncated.** Recording refuses a slug over the
   limit and names the limit that applied. A reader reports an entry whose slug exceeds it as
   malformed, with the same diagnostic as before.

This amends refusal 3 of
[decisions-new-owns-the-write-mechanics](2026-10-24-decisions-new-owns-the-write-mechanics.md):
"kebab-case of at most 80 characters" now reads "kebab-case of at most the register's slug
limit". The rest of that entry stands.

Entries stay at spec 1. A spec version describes what a file says, and no file says its limit: the
limit belongs to whoever reads the register. A reader that applies a lower limit than the
register's caller, including one built before this ruling, reports a longer slug as a malformed
entry and never mis-parses it. That refusal is what
[spec-and-artifact-versioning](2026-08-30-spec-and-artifact-versioning.md) relies on when it warns
that an additive change breaks a strict validator. A register holds a slug over 80 characters only
when its caller has set a higher limit, so every register whose callers set none reads as before.

This ruling is wrong if one run reads and writes the same register under two different limits, if
a reader that does not know a register's limit must accept its longer slugs instead of reporting
them, or if a register must carry a file the tooling parses to state its limit.

### Consequences

* Good, because a register with long slugs, such as the grid's, can be read, linted and written
  without renaming entries that are already cited.
* Good, because the default keeps every existing register's behaviour, so no adopter has to act.
* Bad, because two callers that supply different limits for one register can disagree about
  whether it is clean; a register's station definition is the one place its limit belongs.
