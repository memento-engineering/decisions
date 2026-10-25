# Style guide

How this register's entries are written. Copy this file to `docs/decisions/STYLE.md` and change
it to fit your register. It covers prose only: `SPEC.md` fixes the front matter, the sections and
the force vocabulary, and nothing here can change them.

## Titles

- State the decision, not the topic: "Releases are cut from main", not "Release branching".
- One sentence, sentence case, no full stop. A title that needs two clauses may join them with a
  semicolon.
- Derive the slug from the title, shortening it only where the title is long.

## Voice

- Present tense, and name who acts: "The CLI refuses...", "A reviewer checks...".
- Plain words over jargon. Put code, paths and commands in backticks.
- Say who ruled when a person did, with the date: "(Alex's ruling, 2026-03-02)".

## Sections

- **Context and Problem Statement** leads with what forced the decision: the failure, the
  request, the constraint. Two or three sentences is often enough.
- **Decision Outcome** opens with the rule in one sentence, so a reader can comply without
  reading further. Detail follows; a numbered list suits a decision with several parts.
- **Consequences** lists real effects as `Good, because...` and `Bad, because...`. Name at least
  one cost. If you cannot, the decision may not be one.
- **Considered Options** only when options were actually weighed. Omit it rather than invent
  alternatives to reject.

## Length

Short enough to read in two minutes. When an entry grows past that, it is usually two decisions;
record them separately and cite one from the other.

## Citing

- Cite an entry in this register by its slug, or link its file.
- Cite another register's entry as `repo#slug`.
- A citation in prose is not an edge. Add `obsoletes` or `updates` only when this entry replaces
  or amends the one it names.
