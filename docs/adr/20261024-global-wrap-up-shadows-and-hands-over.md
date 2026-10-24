---
type: ADR
status: accepted
date: 2026-10-24
summary: The global skill is named wrap-up even though a personal skill shadows
  a project skill of the same name; it hands over to the repo's own file, and
  its ledger lives under XDG state, asked for by a SessionStart probe.
---

# The global wrap-up shadows a repo's own, and hands over to it

## Context

telik, andrei.md and framestep each carry a `.claude/skills/wrap-up`. A
generic version for every other repo has to live in `~/.claude/skills`, and
Claude Code resolves a name clash between personal and project skills in
favour of the personal one (code.claude.com/docs/en/skills, "Resolve skills
that share a name": with `deploy` in both, `/deploy` runs the personal one).
So a global `wrap-up` would silently replace each repo's own.

The skill also depends on a ledger written from the session's first action,
and a skill body is only read when invoked, which for a wrap-up is the end.

## Decision

Name it `wrap-up` anyway, and make its first step a hand-over:
`ledger.sh project-skill` walks from the session directory up to the repo root
for `.claude/skills/wrap-up/SKILL.md`, and if it finds one the skill reads that
file and follows it instead. `/wrap-up` then works in every repo, and the
repos that wrote their own still get theirs, one Read later. If Claude Code
ever reverses the precedence, the project skill runs directly and nothing
breaks.

The ledger lives at `$XDG_STATE_HOME/claude/ledger/<session id>`. The
scratchpad is under `/tmp` and a reboot empties it while the session survives;
a file in the worktree needs a gitignore entry no generic tool can count on.
`ledger-probe.sh` asks for it at SessionStart and is silent wherever
`project-skill` finds a repo's own wrap-up, since that repo's instructions name
their own ledger (telik's `.bin/ledger.<id>`) and two ledger rules in one
context compete. Both questions go through the one script, so the probe and the
skill cannot disagree about which repos have their own.

## Considered Options

- **A distinct name** (`session-wrap-up`): nothing shadowed, but `/wrap-up`
  does nothing in most repos, and in the three that have one both skills are
  listed, so the generic one still needs the same hand-over for when it is
  picked.
- **A line in the global CLAUDE.md for the ledger**: loads in every repo
  forever, including the ones whose own instructions say where their ledger
  goes, and cannot stay quiet there.

## Consequences

A project skill read through the hand-over gets none of the loader's
substitutions (`${CLAUDE_SKILL_DIR}`, `$ARGUMENTS`); the hand-over says to read
`${CLAUDE_SKILL_DIR}` as that file's directory. None of the three uses any
today.
