---
type: ADR
status: accepted
date: 2026-08-09
summary: ADR rules live in the skill body and in the repo's domain.md, never in
  AGENTS.md or CLAUDE.md, because those load in full on every request forever.
---

# ADR rules live in the skill body, not in always-loaded files

## Context

The rules — two gates, five statuses, the record format — have to be somewhere
an agent can reach. The obvious place is `AGENTS.md` or `CLAUDE.md`, which are
already read every session.

## Decision

Rules go in the `record-decision` skill body and in `docs/agents/domain.md`.
Neither `AGENTS.md` nor `CLAUDE.md` carries more than a pointer.

Skills load in two stages: frontmatter `name` and `description` sit in context
permanently, the body only on invocation. Measured on this machine, 46 skills
cost 4k tokens standing — roughly 87 each. So triggers go in the description,
where they must always be visible, and everything else in the body, where it
costs nothing until used.

The same reasoning governs the hook. Injecting the ruleset on every commit
would cost doc-size times commits-per-session — around 30k tokens a session —
to answer a question that is almost always "no". The probe is therefore a
pointer of about 25 tokens, never the rules.

## Consequences

A realistic session of 20 commits and 2 records costs roughly 3.6k tokens:
~85 standing, ~500 in probes, ~3k for the two skill-body loads.

The failure mode to watch for is someone "helpfully" moving the rules into
`CLAUDE.md` to make them more reliable. That would add their full size to every
request in every project, permanently, and this record exists to explain why
it was not done.
