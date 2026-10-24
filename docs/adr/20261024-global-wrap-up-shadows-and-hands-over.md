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
`ledger-probe.sh` asks for it at SessionStart. It is silent only where the
repo asks for its own ledger from an always-loaded file (`ledger.sh
repo-ledger`), since two ledger rules in one context compete; today that is
telik, whose `CLAUDE.md` names `.bin/ledger.<id>`. Having a wrap-up of its own
is not enough: andrei.md asks for a ledger only in its skill body, which is read
at the end, and framestep keeps none, so the probe is the only request a session
there gets. The first version stayed quiet in all three, and its review caught
it.

The probe reads the session's starting directory and the skill reads wherever
the session has since `cd`'d to, so the two can choose differently: a session
that starts outside telik and moves into it records here and wraps up with
telik's skill. The hand-over therefore always reads this ledger too, alongside
whatever the repo's file names.

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

A `/clear` starts a new session ID and so an empty ledger; what the old ID
recorded drops out of the count. Known and unhandled.
