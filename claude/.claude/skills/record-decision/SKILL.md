---
name: record-decision
description: Write an architectural decision or a rejected approach to docs/adr/ as an ADR. Use when a decision is made that would be hard to reverse, when an approach has been tried and abandoned, when a commit lands that encodes either, or when a delegated agent returns having discovered either.
---

# Record a decision

Write the record now, while the reasoning is present. Do not ask permission
first — the record lands in the working tree and is reviewed in the diff like
any other file. Over-capture is recoverable; silent under-capture is not.

## Should this be recorded at all?

Two gates. Answer one of them, not both.

**A decision** — all three must hold:

1. Hard to reverse — the cost of changing your mind later is meaningful.
2. Surprising without context — a future reader will wonder why it was done
   this way.
3. The result of a real trade-off — there were genuine alternatives.

**A rejection** — one test:

> Would a competent person plausibly try this again?

Both also require repo-specificity. "Postgres has advisory locks" is a general
fact. "Advisory locks deadlock under our access pattern" is a record.

If neither gate passes, stop and say nothing.

An alternative dismissed **on paper** is not a rejection record — it is a
`Considered Options` section in the deciding ADR. A rejection record is for an
approach someone actually spent effort on.

## Where records go

Read `docs/agents/domain.md` first — it is the repo's format contract and
overrides anything here if the two disagree. It also says whether the repo is
single- or multi-context, and therefore which `docs/adr/` applies.

If `docs/agents/domain.md` has no ADR section, create `docs/adr/` and seed the
section using the format below, so the repo becomes self-describing to agents
that do not have this skill.

If the repo already uses sequential numbering (`0001-…`), leave those files
alone and write new records date-stemmed. Do not migrate.

## Status

| Status | Means |
|---|---|
| `proposed` | We are going to try this; outcome unknown |
| `accepted` | This is how it works |
| `rejected` | We tried it; it did not work |
| `superseded` | Was true, now replaced — set `superseded_by` |
| `deprecated` | No longer applies, nothing replaced it |

Records are append-only. Never delete one. A `rejected` record is the highest
value file in the directory: it is the only artifact that can stop a path being
re-tried, because the code contains no trace of it.

`rejected` may be entered directly, with no prior `proposed`. Most dead ends
are not deliberate choices made in advance.

## Format

Filename `docs/adr/YYYYMMDD-slug.md` — date-stem, no `ADR-` prefix.

```markdown
---
type: ADR
status: rejected
date: 2026-08-09
summary: One sentence, so the directory can be skimmed without opening files.
superseded_by: 20260815-other-record
---

# Short title, no ID

## Context
Why this came up.

## What was tried
Specific enough that someone about to re-attempt it recognises themselves.

## How it failed
The observable symptom, with numbers where they exist.

## What would make it viable
Or an explicit "nothing; this is structural".
```

For a decision, use **Context / Decision / Consequences** instead, the last
only if there are non-obvious downstream effects. Add `Considered Options` only
when the rejected alternatives are worth remembering.

Sections differ by status on purpose. Fixed headings across both would force
empty sections, and an empty section is worse than an absent one.

`superseded_by` and `supersedes` hold the filename **stem** exactly.

Length is whatever the reasoning requires. No template padding, no section
written because it exists. The minimum is a title, frontmatter, and a
paragraph.

## Procedure

1. **Check for a duplicate.** List `docs/adr/` for today's date-stem. Several
   triggers can fire on one decision. If a record already covers it, edit that
   record instead of adding another.
2. **Redact.** Rejection records quote error output, which quotes connection
   strings, tokens and hostnames. Remove them before writing.
3. **Write the file.**
4. **Commit separately.** The probe fires *after* a commit, so the record
   cannot join it. Use a follow-up commit — this matches the repo's "group
   related changes into separate, logical commits" convention:

   ```
   docs(adr): record why per-request pooling was rejected
   ```

   Reference the triggering commit by SHA in the body.
5. **Say one line** about what you recorded. Do not summarise the record back.
