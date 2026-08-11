# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 20260805-event-sourced-orders.md
│   └── 20260812-postgres-for-write-model.md
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_

## Writing ADRs

This section is the repo's format contract and **overrides any template
bundled with a skill or plugin**. `/domain-modeling` ships its own
`ADR-FORMAT.md` using sequential numbering and a bold status line; where the
two disagree, this file wins.

It is stated here, in the repo, rather than only in a skill, so that an agent
without this machine's dotfiles — a collaborator, a CI run, another harness —
can still produce a conforming record.

### When to write one

**A decision** needs all three: hard to reverse, surprising without context,
the result of a real trade-off.

**A rejection** needs one test: would a competent person plausibly try this
again? An approach dismissed on paper is a `Considered Options` section in the
deciding ADR, not a record of its own — a rejection record is for something
someone actually spent effort on.

### Naming

`docs/adr/YYYYMMDD-slug.md`. Date-stem, no `ADR-` prefix. Date-stems are minted
locally, so parallel agents and worktrees cannot collide the way sequential
numbering does.

Repos already using `0001-` style keep those files. New records are
date-stemmed; do not migrate.

### Frontmatter

`type`, `status`, `date` and `summary` are required. `supersedes` and
`superseded_by` hold a filename **stem** exactly.

```yaml
---
type: ADR
status: rejected
date: 2026-08-09
summary: One sentence, so the directory can be skimmed without opening files.
superseded_by: 20260815-other-record
---
```

### Status

| Status | Means |
|---|---|
| `proposed` | We are going to try this; outcome unknown |
| `accepted` | This is how it works |
| `rejected` | We tried it; it did not work |
| `superseded` | Was true, now replaced |
| `deprecated` | No longer applies, nothing replaced it |

Records are append-only — never delete one. `rejected` may be entered directly
without a prior `proposed`.

### Sections

Decisions use **Context / Decision / Consequences** (the last optional).
Rejections use **Context / What was tried / How it failed / What would make it
viable**.

They differ on purpose. Fixed headings across both would force empty sections,
and an empty section is worse than an absent one.

A rejection is only useful if it answers all three of: what was tried,
specifically enough to recognise a re-attempt; how it failed, with numbers
where they exist; and what would make it viable — or an explicit "nothing,
this is structural". The last distinguishes *don't do this* from *don't do
this yet*.

Length is whatever the reasoning requires. The minimum is a title,
frontmatter, and a paragraph.
