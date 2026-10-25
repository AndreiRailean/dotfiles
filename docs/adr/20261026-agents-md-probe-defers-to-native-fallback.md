---
type: ADR
status: accepted
date: 2026-10-26
summary: agents-md-probe stays quiet wherever Claude Code's own AGENTS.md
  fallback (2.1.277+) is on, and fires only when a CLAUDE.md, .claude/CLAUDE.md
  or CLAUDE.local.md has switched it off and an AGENTS.md goes un-imported.
---

# agents-md-probe defers to the native AGENTS.md fallback

## Context

The probe and the `point-claude-at-agents-md` skill were built on the premise
that Claude Code never loads `AGENTS.md`, which was true as of 2.1.269. 2.1.277
added a fallback, the default `instructionFiles` mode
`claude-md-or-agents-md`. The probe kept firing in every repo whose
`AGENTS.md` nothing imported, and told those sessions their conventions were
missing when they were already in context.

The fallback's scope isn't documented beyond "a project with no CLAUDE.md".
It was read out of the 2.1.308 bundle and then confirmed with `claude -p` in
throwaway repos, asking for a codeword that only `AGENTS.md` held:

| Repo | `AGENTS.md` loaded? |
|---|---|
| `AGENTS.md` only, under `/tmp` | yes |
| `AGENTS.md` only, under `~` (beside the global `~/.claude/CLAUDE.md`) | yes |
| plus a `CLAUDE.md` that doesn't import it | no |
| plus only an untracked `CLAUDE.local.md` | no |

The switch is per session, not per directory. A `CLAUDE.md`,
`.claude/CLAUDE.md` or `CLAUDE.local.md` in the session directory or any
directory above it switches the fallback off. Then no `AGENTS.md` loads,
nested ones included, unless a `CLAUDE.md` imports it.

## Decision

Keep the probe and the skill, and narrow the probe to the case that still
loses conventions silently. It walks from the session directory up to the repo
root, checking on disk rather than in git, because `CLAUDE.local.md` is
usually gitignored. It exits quietly unless one of the three files turns up.
Past that point the per-`AGENTS.md` check is unchanged: each one needs a
sibling `CLAUDE.md` that mentions it.

This repo keeps its explicit `@AGENTS.md` import. Without it, one machine's
`CLAUDE.local.md` would drop the conventions there and nowhere else.

## Considered Options

- **Retire the probe and the skill.** That would leave the remaining failure
  uncovered: a repo with both files and no import still hands Claude nothing
  from `AGENTS.md`. So does a developer's local `CLAUDE.local.md`.
- **Keep firing on every un-imported `AGENTS.md`.** That case is now a false
  alarm with a false message. It also pushes sessions to add a `CLAUDE.md` a
  repo doesn't need.
- **Read the `instructionFiles` setting and branch on it.** Settings merge
  across user, project, local and managed layers. The probe would have to
  reimplement that precedence in `sh`, so it assumes the default instead.

## Consequences

- If someone sets `instructionFiles` to `"claude-md"`, nothing loads
  `AGENTS.md` in a repo that has only that file, and the probe stays quiet
  there. That gap is accepted.
- The probe encodes behaviour the CLI doesn't document: the walk stops at the
  repo root, the global file doesn't count, and `CLAUDE.local.md` does. It was
  verified against 2.1.308. `tests/test-agents-md-probe.sh` pins the probe to
  these assumptions but can't notice the CLI changing them. If an upgrade
  changes the "Project instructions" option in `/config`, rerun the table
  above with the skill's Verify recipe.

Landed in 6f8910b (PR #27).
