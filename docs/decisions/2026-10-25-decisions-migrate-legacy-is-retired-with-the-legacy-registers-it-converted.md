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
  slug: "decisions-migrate-legacy-is-retired-with-the-legacy-registers-it-converted"
  surfaces:
    - "cli/dart/decisions/lib/src/command.dart"
    - "cli/dart/decisions/lib/decisions.dart"
    - "cli/dart/decisions/lib/src/instructions_command.dart"
    - "README.md"
  obsoletes: []
  updates: []
  obsoleted-by: null
  updated-by: []
  bead: "dec-3zk"
  legacy-id: null
---

# decisions migrate-legacy is retired with the legacy registers it converted

## Context and Problem Statement

`decisions migrate-legacy` converted one `docs/adr/ADR-0000` "AI decision register", plus any
ratified `ADR-000N` documents named with `--ratified`, into spec-1 entries with empty edges. It was
the script that `memento-engineering#legacy-register-migration` called for. It was a one-time
converter for a retired format. It never upgraded a register from one spec to the next.

That conversion is finished. `memento-engineering#register-is-the-only-decision-system` obsoleted
the migration entry on 2026-09-13. It records that no repo keeps an `ADR-0000` document any more and
that none should be re-created. The verb had nothing left to convert, but the binary still listed
it, `prime` still told agents to reach for it "once, to convert an ADR-0000 register", and the
package still exported its library (`LegacyRegisterConverter`, `LegacyRegisterConversionService`,
`LegacyRatifiedAdr`, `LegacyConversionResult`, `LegacyConversionException`,
`LegacyRegisterRefused`). A read-only search of the org checkout found no caller of any of them
outside this repo, and the grid adapter does not use them. The verb also crashed when it refused
an input: the exception went uncaught, so it printed a stack trace and exited 255.

## Decision Outcome

**`decisions migrate-legacy` is retired, together with the legacy registers it converted.** Nico
judged the verb dead on 2026-10-25. The agent chose how to remove it.

1. **The verb goes.** The command and its constructor and runner parameter (`legacyConverter`) are
   removed, and so is its `prime` cue. The README's tier table and Status section stop listing it.
2. **The library goes.** `lib/src/legacy.dart` and its export from `package:decisions` are removed,
   along with their tests and the `legacy_register` fixture. This is a breaking change to the
   package API. The package is 0.x, so the next release is a minor bump.
3. **The refusal crash is not fixed first.** No register needs the verb, so fixing its error path
   would only polish code that is being deleted.
4. **`legacy-id` stays.** The field is part of spec 1, entries that were converted carry it, and
   the graph, the index and cross-register references still resolve an entry by its legacy id. The
   format does not change, so entries stay at `register.spec: 1`, as
   [spec-and-artifact-versioning](2026-08-30-spec-and-artifact-versioning.md) requires.

That entry's rule that a breaking spec bump ships its migration tool covers spec bumps.
`migrate-legacy` converted a format that predates spec 1, so this removal does not touch that
rule. [spec-tier-table-describes-capabilities-and-defers-the-verb-list-to-the-cli](2026-10-25-spec-tier-table-describes-capabilities-and-defers-the-verb-list-to-the-cli.md)
lists `migrate-legacy` among the verbs the binary shipped. That was a fact about its context, not
part of its decision, so it is cited here and not amended.

### Consequences

* Good, because the binary, `prime` and the README no longer offer agents a verb that has no input
  left anywhere in the org.
* Good, because the package's public API loses six types that had no callers.
* Bad, because anyone who still holds an `ADR-0000` register outside the org has to convert it
  with a release that predates this one, or by hand from `templates/decision.md`.
