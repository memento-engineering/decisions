# Style guide

How entries in this register are written. It governs the prose only; [`SPEC.md`](../../SPEC.md)
fixes everything else.

## Titles

- A declarative sentence that states the rule, in sentence case with no full stop: "The decisions
  CLI ships as prebuilt binaries".
- Two halves of one decision join with a comma and "and", or a semicolon: "decisions new owns the
  write mechanics; the decide skill owns judgement".
- Verb and package names appear bare in the title, as they would be spoken (`decisions new`,
  `STYLE.md`), and in backticks everywhere else.

## Context and Problem Statement

- Lead with what was broken or missing, concretely: the file that failed to parse, the edge no
  verb could write, the step an agent had to transcribe by hand. Measured cases beat general
  claims.
- Then the precedent that constrains the answer, cited inline:
  `memento-engineering#knowledge-lives-in-the-smallest-surface-that-can-enforce-it`.
- A human scope ruling is stated where it bears, with who and when: "On 2026-10-24 nico ruled
  the scope".

## Decision Outcome

- Open with the rule in bold, in one sentence a reader can comply with without reading further.
- A decision with several parts follows with a numbered list, each item led by a bold phrase.
- Name the code that carries the rule (`isDecisionEntryFile`, `tool/generate_guides.dart`) and
  where `SPEC.md` states it, so a reader can find the enforcement.
- Rejected alternatives, when there were real ones, are listed under `## Considered Options` and
  the reason each lost is given in the outcome prose: "Prose-only edges are rejected because...".
  No options section is written for a decision that had no alternatives.
- Human rulings inside the outcome carry the name and date in parentheses: "(nico's ruling,
  2026-10-24)".

## Consequences

- `* Good, because ...` and `* Bad, because ...`, each a full sentence.
- Every entry has at least one honest `Bad`: the release a register now needs, the step that
  became manual, the case that is now skipped silently.

## Form

- Present tense, impersonal: name the verb, the engine or the reader that acts, not "we".
- Paths, verbs, flags, slugs and field names in backticks.
- Cite an entry in this register by slug or a relative link to its file; another register's
  entry as `repo#slug`.
- Wrap at 100 columns.
- Roughly 400 to 750 words. An entry that runs longer is usually two decisions.
