# Automatic ADR capture — design

Date: 2026-08-09
Repo: personal dotfiles (Stow-managed; macOS / WSL / Linux)

## Goal

Make architectural decisions **and failed approaches** get written down as they
happen, without the user having to ask.

The measurable baseline is 1 ADR across 88 commits, and that one
(`docs/adr/0001-no-shared-shell-library.md`) was written deliberately on
2026-08-05 by a session that no longer exists on disk. Nothing has been captured
since.

The cause is structural, not a matter of diligence. `docs/agents/domain.md`
governs how agents **consume** ADRs — read them before exploring, use the
glossary's vocabulary, flag conflicts. There is no counterpart governing
**production**. That is delegated entirely to `/domain-modeling`, which is
user-invoked, is instructed to "offer ADRs sparingly", and whose verb is *offer*
rather than *write*. It behaves as designed; the design is to stay quiet.

The same failure applies to `/handoff`: it produces good output but only when
explicitly invoked, which in practice happens only when running out of context.
**Any mechanism that depends on the user remembering to invoke it has already
failed.** This design is therefore built around events that fire on their own.

### Why negative results specifically

An accepted decision leaves evidence in the code — a reader can at least see
*what* was chosen. A rejected approach leaves nothing: no diff, no artifact,
nothing to review. It is the only class of knowledge that is unrecoverable from
the repository itself, and it is what stops the next person re-treading a path
that has already been shown not to work.

## Decisions

- **One record type, not two.** Negative results are ADRs with
  `status: rejected`, not a separate `type: negative-result` document. This
  preserves the supersession link between a failure and what replaced it, which
  is worth more than the two facts held separately.
- **`rejected` is enterable directly**, without passing through `proposed`. Most
  dead ends are not deliberate choices made in advance — requiring an upfront
  `proposed` record for everything tried would drown the directory and would
  miss precisely the incidental discoveries worth keeping.
- **Two admission gates, selecting status rather than type.** A decision needs
  all three of hard-to-reverse, surprising-without-context, real-trade-off
  (unchanged from upstream, so ADR scarcity is preserved). A rejection needs one
  test: *would a competent person plausibly try this again?*
- **Date-stem IDs**, `YYYYMMDD-slug.md`, no `ADR-` prefix. Sequential numbering
  requires allocating against a shared view of the directory, making it a
  contention point under parallel agents and worktrees. Date-stems are minted
  locally with no coordination, and sort chronologically in `ls`.
- **Frontmatter for metadata, prose for content.** A `**Status:** …` line has to
  be regex-matched out of prose and breaks on reflow; silent wrongness in a
  decision index is worse than no index. This also realigns with upstream, which
  specifies frontmatter — ADR-0001's bold line is the local deviation.
- **A one-sentence `summary` field**, so a directory can be skimmed without
  opening files, an index can be generated, and GitHub renders it in the
  frontmatter table.
- **Hooks guarantee the question is asked; the skill decides the answer.** A
  hook cannot judge whether a diff encodes a decision, but it can guarantee
  nothing passes unexamined — which is the part failing today.
- **Rules live in the skill body**, never in `AGENTS.md` or `CLAUDE.md`.
  Always-loaded files cost their full size on every request forever; a skill
  body costs nothing until invoked. See Token budget below.
- **Do not edit `domain-modeling` in the plugin cache.** It lives under
  `~/.claude/plugins/cache/` with `autoUpdate: true`; any edit is reverted by
  the next plugin update. Recorded as a rejected ADR because it is the obvious
  first instinct.
- **`Considered Options` is retained** for its upstream purpose. An alternative
  dismissed *on paper* is a section in the deciding ADR; an approach *actually
  tried and failed* earns its own `rejected` record. The test is whether
  anyone spent effort on it.

## Architecture

Three files in the existing `claude` stow package, deploying to every machine:

```
~/.dotfiles/claude/.claude/
├── settings.json                        ← add a hooks block
├── skills/record-decision/SKILL.md      ← NEW  gates, format, procedure
└── hooks/adr-probe.sh                   ← NEW  probe emitter
```

### `record-decision` skill

Model-invocable — explicitly **not** `disable-model-invocation: true`, which is
what makes the mattpocock slash-commands inert unless typed.

- **Description** (always in context, ~70 tokens): the trigger conditions.
- **Body** (loaded only on invocation): the two gates, the status lifecycle, the
  record format, redaction, and the write procedure.

Repo-specific structure is *not* duplicated here. The skill defers to
`docs/agents/domain.md`, which already specifies single- vs multi-context layout
and where `docs/adr/` lives.

### `adr-probe.sh`

One script, two hook registrations. It performs no judgment and writes no files
— that keeps it fast, independently testable, and unable to corrupt the repo.

| Hook | Matcher | Fires on |
|---|---|---|
| `PostToolUse` | `Bash` | every Bash call; script filters for `git commit` |
| `SubagentStop` | — | every delegated agent returning |

Matchers match the **tool name**, not command text, so the PostToolUse hook is
invoked on every Bash call and must itself inspect `tool_input.command` from the
stdin JSON. The script therefore stays a dozen lines of bash with no interpreter
startup, and exits 0 silently in every case it does not care about.

Output on a hit:

```json
{"hookSpecificOutput": {
  "hookEventName": "PostToolUse",
  "additionalContext": "A commit just landed. Does it encode a decision, or record an approach tried and abandoned? If yes, invoke record-decision. If no, continue silently."}}
```

Both `PostToolUse` and `SubagentStop` accept `additionalContext` (verified
against the 2.1.224 bundle). Note that on `SubagentStop` it is *"delivered to
the subagent"*, not the parent — so a subagent writes its own record. Date-stem
IDs make this safe without locking.

### Third trigger

Model judgment mid-session, via the skill firing on its own. This is the weakest
of the three — it is the mechanism demonstrably not firing today — and is
retained but not relied upon. The two hook-driven triggers are structural.

## Status lifecycle

| Status | Means | Entered when |
|---|---|---|
| `proposed` | We are going to try this; outcome unknown | A deliberate, costly-to-try choice is made |
| `accepted` | This is how it works | It worked |
| `rejected` | We tried it; it did not work | Directly, or from `proposed` |
| `superseded` | Was true, now replaced | A later ADR replaces it (`superseded_by`) |
| `deprecated` | No longer applies, nothing replaced it | The context it served went away |

Records are **append-only**. Nothing is ever deleted, and a status change is an
edit to that record plus, where relevant, a new record citing it. A `rejected`
ADR is the highest-value file in the directory — it is the only artifact that
can stop a path being re-tried, because the code contains no trace of it.

The full chain, for a deliberate choice that failed:

```
20260809-per-request-pooling.md   status: proposed  → rejected
                                  superseded_by: 20260815-shared-pool…
20260815-shared-pool-with-semaphore.md   status: accepted
                                  supersedes: 20260809-per-request-pooling
```

The replacement's body cites why its predecessor failed, so the *link* survives
rather than two disconnected facts.

## Record format

```markdown
---
type: ADR
status: rejected
date: 2026-08-09
summary: Per-request connection pooling deadlocks above ~200 rps because
  acquisition happens inside an open transaction.
superseded_by: 20260815-shared-pool-with-semaphore
---

# Per-request connection pooling

## Context
Request latency spiked under load; pooling was the obvious lever.

## What was tried
A fresh `Pool` per request, default ceiling of 10 connections.

## How it failed
Deadlocked above ~200 rps. Pool acquisition blocked while holding a
transaction, so connections were never returned under contention.

## What would make it viable
Nothing at this ceiling — the deadlock is structural to acquiring inside an
open transaction, not a tuning problem.
```

- `superseded_by` / `supersedes` hold the filename **stem** exactly, so
  resolution is string-to-path with no parsing.
- The H1 carries no ID. The ID is the filename and the frontmatter; repeating it
  goes stale on rename.
- **Sections differ by status.** Decisions use Context / Decision /
  Consequences (the last optional); rejections use the four above. Fixed
  headings across both would force empty sections, and an empty section is
  worse than an absent one.
- **Length is whatever the reasoning requires.** Upstream says "1–3 sentences";
  ADR-0001 is 110 lines and is better for it. No template padding, no section
  written because it exists. Minimum viable is a title, frontmatter, and a
  paragraph.

### What a rejection must contain

"We tried X, it didn't work" is close to useless — it tells the next reader
nothing about whether their variation fails too. Three things are required:

1. **What was tried** — specific enough to recognise a re-attempt.
2. **How it failed** — the observable symptom, with numbers where they exist.
3. **What would make it viable** — or an explicit "nothing; this is structural".

The third distinguishes *don't do this* from *don't do this yet*, and is the
part that ages well. ADR-0001's "When to extract" section already does this;
the rule generalises existing local practice rather than importing one.

## Divergence from upstream `ADR-FORMAT.md`

Deliberately minimised. Same location, same lazy directory creation, same
`# Short title` H1, same frontmatter-for-status, same optional `Consequences`
and `Considered Options`, same three-part decision gate.

Three genuine divergences, each load-bearing:

| | Upstream | Here | Why |
|---|---|---|---|
| Filename | `0001-slug.md` | `YYYYMMDD-slug.md` | local minting under parallel agents |
| Status values | `proposed \| accepted \| deprecated \| superseded by ADR-NNNN` | adds `rejected` | the point of the exercise |
| Supersession | inside the status string | `status: superseded` + `superseded_by:` | keeps status parseable |

`rejected` is not upstream's `deprecated`: deprecated means *was true, no longer
applies*; rejected means *never adopted*. Both are kept.

`type`, `date`, `summary` and the rejection headings are additive — nothing
contradicts upstream, so records written by `/domain-modeling` in another repo
remain readable here.

## Commit sequencing

`PostToolUse` fires *after* the commit completes, so the ADR cannot land in the
commit that triggered it. Amending rewrites history and is unsafe once pushed;
`PreToolUse` does not help because the file would not be staged either. The ADR
therefore lands in a follow-up commit:

```
feat(pool): bound concurrency at the semaphore
docs(adr): record why per-request pooling was rejected
```

This matches the existing convention in `AGENTS.md` — *"Group related changes
into separate, logical commits"* — rather than working around it. The ADR body
references the triggering commit by SHA, giving a code → commit → ADR trail.

## Token budget

Skills load in two stages: frontmatter `name` + `description` sit in context
permanently, the body only on invocation. `/context` measures 46 skills at 4k
tokens standing, ~87 each. Anything that must always be visible goes in the
description; everything else in the body.

The hook is where this could go wrong. Injecting the full ruleset on every
commit would cost doc-size × commits-per-session — roughly 30k tokens a session
— to answer a question that is almost always "no". The probe is therefore a
pointer, never the rules.

| | Cost |
|---|---|
| Standing (skill description) | ~70 tokens |
| Per commit probe | ~25 tokens |
| Per ADR actually written (body loads) | ~1.5k tokens |
| Realistic session — 20 commits, 2 ADRs | **~3.6k tokens** |

## Degradation

This deploys globally and will fire in every repo.

- No `docs/adr/` → created lazily on first real write, per `domain.md`.
- No `docs/agents/domain.md` → assume single-context, `docs/adr/` at repo root.
- Not a git repo → probe exits silently, zero cost.
- `CONTEXT-MAP.md` present → resolve the context-scoped `docs/adr/` per
  `domain.md`.

## Dependencies and portability

The mechanism is machine-global; the convention must be repo-local.

| | Lives in | Travels with |
|---|---|---|
| `record-decision` skill, `adr-probe.sh`, hooks block | dotfiles → `~/.claude/` | **the user**, not the repo |
| Record format, statuses, gates | `docs/agents/domain.md` | **the repo** |

Putting everything in the skill body works on machines with these dotfiles and
fails everywhere else — a collaborator, a CI agent, a Pi or Codex session, or
the same user on a box without dotfiles. None can produce a conforming record
because nothing in the repo says what one is.

So `docs/agents/domain.md`, which today governs consumption only, becomes the
**format contract**: frontmatter fields, the five statuses, date-stem naming,
and what a rejection must contain. Any agent that reads it can then write a
valid record when asked. The skill narrows to *triggering and procedure* — when
to write, plus redaction and dedup. The repo owns what a record **is**; the
machine owns when one **gets written**. No rule is stated twice, and domain.md
is read on demand, so this costs nothing standing.

`record-decision` seeds the ADR section of `domain.md` if it is absent when
first writing in a repo, so a new repo needs no external setup.

### What is required

- **Dotfiles installed.** `claude` is already in `PACKAGES` (`install.sh:156`,
  `doctor.sh:24`), so files added under `claude/.claude/` are stowed and
  drift-checked with no wiring changes.
- **A new session.** `~/.claude/skills/<name>/` auto-loads *next* session as
  `<name>@skills-dir`; it is not picked up by the session that installed it.

### What is not required

- **The `mattpocock-skills` plugin.** It seeded `docs/agents/domain.md` via
  `/setup-matt-pocock-skills`, but that file is now a repo-local artifact.
  `record-decision` carries its own gates and format and never invokes
  `domain-modeling`. The plugin remains useful for `CONTEXT.md` glossary
  maintenance and interactive design-time ADRs, but is not load-bearing here.

### Known risk: two writers, two format sources

`domain-modeling` writes ADRs from its own bundled `ADR-FORMAT.md` — sequential
numbering, bold status line — which conflicts with this format, and it
auto-updates, so upstream can change without warning. The mitigation is to make
`docs/agents/domain.md` the repo's stated authority and record the override
there. That is a convention, not a mechanism: a `domain-modeling` invocation
that does not read domain.md first can still emit a non-conforming record. Such
records remain readable (the divergences are narrow) and can be normalised by
hand. Revisit if it happens more than occasionally.

## Failure modes

| Mode | Mitigation |
|---|---|
| **Probe ignored** — read and passed over | Phrased as a direct question, not a suggestion; backed by triggers in the always-loaded skill description. The likeliest failure; must be measured, not assumed |
| **Duplicate records** across triggers | Skill globs `docs/adr/{today}-*` before writing and merges rather than adds |
| **Secrets in ADRs** — rejections quote error output, which quotes connection strings | Explicit redaction step in the skill body; `/handoff` sets the precedent |
| **Noise** — records for changes that did not earn one | Gates first, PR diff as human backstop. Over-capture is recoverable; silent under-capture is not |
| **Hook failure** | Script always exits 0; it runs after the commit and cannot block one |
| **Unwanted repos** | Silent exit outside a git repo. A `.no-adr` opt-out only if it proves necessary |
| **Worktree divergence** | Date-stems cannot collide; merges cleanly unless two agents pick the same slug |
| **Per-Bash-call subprocess cost** | Script stays trivial; measure if noticeable |
| **Subagent cannot write** — `Explore` and `Plan` are defined as all tools *except* `Write`, so they can reach the gate and be unable to act on it | Probe inspects `agent_type` from the `SubagentStop` payload; for write-less types it instructs the agent to return the finding as text for the parent to record |
| **Other harnesses have no hooks** — `PostToolUse`/`SubagentStop` are Claude Code constructs, absent in Pi and Codex | Capture degrades to model judgment against `docs/agents/domain.md`. This is the main reason the format contract is repo-local |
| **Collaborators produce nothing** — anyone without these dotfiles commits normally and triggers nothing | Accepted. This is the case the out-of-scope CI backstop would cover |

## Migrations

1. `docs/adr/0001-no-shared-shell-library.md` → `20260805-no-shared-shell-library.md`
   via `git mv`; convert the `**Status:** … · **Date:** …` line to frontmatter
   and add a `summary`. Content unchanged.
2. `docs/agents/domain.md` is promoted from a consumption guide to the repo's
   **format contract**. It currently documents sequential numbering with
   `0001-…` / `0002-…` examples, which must change to date-stems, but the
   larger change is additive — it gains the frontmatter field list, the five
   statuses, what a rejection must contain, and an explicit statement that this
   repo's format overrides any skill's bundled template. Without this, the repo
   is unreadable to any agent lacking these dotfiles (see Dependencies and
   portability).

### Other repos: coexistence, not migration

The two migrations above apply to this repo only. When `record-decision` lands
in a different repo that already has sequentially numbered ADRs, it leaves them
alone and writes new records date-stemmed. `domain.md` documents the current
convention; the older files remain valid history.

Both forms parse and both sort, and a forced rename across an unfamiliar repo
risks breaking inbound links for tidiness that buys nothing. Renaming is always
available later as a deliberate act.

## Out of scope

Deliberately excluded, and each is a plausible later addition:

- **Transcript archiving and session↔commit linking.** A `Claude-Session:`
  commit trailer plus an out-of-band transcript archive keyed by session ID.
  Discussed and wanted, but independent of this work.
- **CI or `prepare-commit-msg` enforcement.** Deterministic and works for
  human-authored commits, but cannot judge significance, so it demands ADRs for
  changes that do not warrant them — and a noisy gate gets routed around. Worth
  reconsidering once the capture rate is known.
- **A `tags:` frontmatter field.** Obvious to want, no consumer yet.
- **A generated ADR index.** The `summary` field exists to make this cheap
  later.

## Verification

Success is measurable and the baseline is known:

```
ls docs/adr/ | wc -l        vs      git rev-list --count HEAD
```

Currently 1 / 88. The meaningful signal is not a target count but whether
`status: rejected` records appear at all — under the current setup their rate is
structurally zero, since nothing else in the toolchain can produce them.
