# Clarify the source repository README

## Implementation Plan

1. Clarify one paragraph without changing executable behavior.

## Touches

- `source_repo/README.md` — documentation clarification.

## ADR Alignment

No decision applies — the roster-wide `decisions index --surface source_repo/README.md` query returned an empty `decisions` array.

## Validation Plan

- Run `git diff --check` and expect exit code 0.
