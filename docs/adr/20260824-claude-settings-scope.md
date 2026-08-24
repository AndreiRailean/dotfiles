---
type: ADR
status: accepted
date: 2026-08-24
summary: claude/.claude/settings.json is a live file Claude Code writes to in a
  public repo, so it holds generic preferences only and a pre-push allowlist
  test blocks anything machine- or employer-specific.
---

# Claude settings scope is enforced, not trusted

## Context

`~/.claude/settings.json` is a symlink into this repo, and this repo is public.

Tracking the real file rather than a template is deliberate, and
[20260811-stow-managed-hook-activation](20260811-stow-managed-hook-activation.md)
depends on it: editing the repo file changes the live configuration with no
install step. The cost is that Claude Code, not a person, decides what gets
written there. Auto-mode onboarding, a plugin toggle, a `/config` change — all
of them append to a tracked file in a public repo with no human in the loop.

That misfired. An auto-mode onboarding pass wrote an `autoMode` block holding
an employer's org name, its private repo, CI secret *names*, internal service
inventory, internal hostnames, and the mechanism gating its production
deploys. No secret values — but a reconnaissance map of someone else's
infrastructure, one `git push` from being public.

It was caught by reading a diff before pushing. That is the whole problem: the
only control was a human noticing, and the file is written by something that
does not announce what it wrote.

## Decision

`claude/.claude/settings.json` holds **generic, portable preferences only** —
values that would be identical on a stranger's laptop. Anything machine-,
employer-, or project-specific belongs in that project's own
`.claude/settings.local.json`, which is gitignored and sits closer to the code
it describes.

`tests/test-claude-settings-scope.sh` enforces it, and `install.sh` installs a
`pre-push` hook that runs it.

The key check is an **allowlist** of known-generic keys, not a denylist of
risky ones. Claude Code gains settings keys on its own schedule; a denylist
passes silently on whichever new key first carries organisational detail.
Failing on the unknown means a leak can only ever be loud.

The test also scans values, because an allowlisted key can carry machine
detail inside it — a permission rule scoped to an absolute worktree path, a
hook command pointing at somebody's home directory.

## Considered Options

**Commit the project-specific config to the work repo instead.** That repo is
private, so the org detail would be safe there, and every worktree would get
it with no sharing step. Rejected because it makes personal allow-rules
team-wide config: colleagues inherit them and they surface in review.

**Untrack `settings.json` behind a `.example` template**, matching the
`shell/local.sh` and `git/local` convention already in this repo. This is the
strongest option and remains the fallback — it makes the leak structurally
impossible rather than merely detected. Rejected for now because it gives up
write-through: generic preferences would stop syncing between machines, which
is the reason the file is tracked at all. The guard keeps the benefit and
prices in the risk.

**A denylist of known-risky keys.** Simpler and quieter, and wrong for the
reason given above.

## Consequences

Adding a genuinely generic preference now requires adding its key to the
allowlist. This is a deliberate one-line review step, not an oversight: the
test failing on an unrecognised key is the mechanism, so it cannot be made
quiet without removing the protection.

**The guard names no employer, domain, or project.** Hardcoding those to grep
for them would put the identifiers into the public repo the test exists to
keep them out of. Every pattern is generic — absolute home paths,
secret-shaped variable names. The same constraint binds commit messages and
this record: a log is as public as a file.

A fresh clone is **unguarded until `install.sh` runs**, because `.git/hooks`
is not tracked and cannot be. The installer is the only path to every machine.
This is a real gap, narrowed only by the fact that a fresh clone has nothing
machine-specific in it yet.

The project-local file is shared across that project's worktrees with
`git worktree-share`, so permission rules Claude learns in one worktree apply
in all of them. For a single project that is usually wanted, and it matches
how `.env.local` is already shared — but it is a widening of scope, not a
neutral detail.

The rule generalises: **tracking a live, tool-written file in a public repo
makes every future write by that tool a publication decision that nobody
reviews.** Where that trade is worth making, the reviewer has to be a test.
