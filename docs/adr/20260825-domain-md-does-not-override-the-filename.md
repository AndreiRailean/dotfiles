---
type: ADR
status: accepted
date: 2026-08-25
summary: A repo's domain.md overrides the skill on what a record contains but not on what it is called, because a stale domain.md would otherwise silently disable the date-stem convention.
---

# domain.md wins on content, not on the filename

## Context

[20260809-rules-in-skill-body](20260809-rules-in-skill-body.md) put the ADR
rules in two places — the `record-decision` skill body and each repo's
`docs/agents/domain.md` — so that an agent without these dotfiles can still
produce a conforming record. It did not settle which one wins when they
disagree, and the skill resolved that on its own by telling the agent to read
domain.md first and let it override "anything here if the two disagree".

That is the right default for almost everything in the file. It is wrong for
the filename, and the failure is silent rather than loud.

ratpack-sell is the case that surfaced it. Its `docs/agents/domain.md`
documented `docs/adr/0001-<decision>.md`, because that is what
`/domain-modeling` seeded and nobody revisited. `record-decision` read it,
concluded the repo's contract was sequential numbering, and deferred — every
time it fired, for nineteen records. The date-stem convention had never once
applied in that repo, and nothing reported that: the skill was working exactly
as written.

It ended the way sequential numbering ends. On 2026-08-25 two records were both
numbered `0019`, written on parallel branches nine minutes of committing apart,
because a sequential number has to be guessed from the state of branches the
author cannot see.

## Decision

domain.md overrides the skill on the *content* of a record — sections, length,
what clears the bar. It does not override the filename. New records are
`YYYYMMDD-slug.md` whatever a repo doc or a bundled plugin template says, and a
domain.md that disagrees is fixed in the same change rather than obeyed.

`tests/test-adr-skill.sh` asserts the carve-out is stated, so a future
tidy-up of the precedence prose cannot quietly restore the old behaviour.

## Considered Options

**Leave precedence blanket, fix ratpack-sell's domain.md.** Rejected. It treats
a structural hole as one repo's stale file. Every repo seeded by
`/domain-modeling` starts with a domain.md prescribing sequential numbering, so
the convention is disabled by default in exactly the repos that have never
thought about it — and it fails closed and silent, which is how it survived
nineteen records.

**Make the skill override domain.md entirely.** Rejected. domain.md is the only
thing a collaborator, a CI run or another harness reads, and it is the reason
the rules were duplicated into the repo in the first place. Demoting it
wholesale would undo [20260809-rules-in-skill-body](20260809-rules-in-skill-body.md).

## Consequences

Precedence is now split rather than uniform, which is more to hold in mind than
"the repo always wins". The split is justified by the failure mode, not by
taste: content disagreements are visible in the written record and get caught
in review, whereas a filename disagreement produces a conforming-looking record
under the wrong convention and is caught only when two of them collide.

An agent adopting the convention in a repo with existing `0001-` records now
does two things rather than one — writes date-stemmed, and updates domain.md.
The alternative is that the second never happens and the next agent inherits
the same silent override.
