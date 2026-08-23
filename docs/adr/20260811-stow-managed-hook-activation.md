---
type: ADR
status: accepted
date: 2026-08-11
summary: A hook registered in stow-managed settings.json goes live on git pull
  but its script only arrives on install.sh, so the registration must tolerate
  a missing script.
---

# Stow-managed hook registration activates before its script exists

## Context

`~/.claude/settings.json` is a symlink into this repo. Editing the repo file
changes the live Claude Code configuration immediately — there is no separate
install step for it.

`~/.claude/hooks/adr-probe.sh` is not like that. It is a per-file symlink that
only exists once `install.sh` runs stow.

So a `git pull` that brings in both files arms the hook instantly and delivers
the script later. In the gap, the registered command is `sh` against a path
that does not exist, which exits 2 — the code Claude Code reads as a *blocking*
PostToolUse error. Every Bash call in the session fails, including the ones
needed to run `install.sh`.

This is not theoretical. It happened during this branch's own development: the
hook was registered in one commit, the script had not been stowed, and every
subsequent command raised a blocking hook error until the symlink was created
by hand.

## Decision

The registration guards itself:

```
[ -r "$HOME/.claude/hooks/adr-probe.sh" ] && sh "$HOME/.claude/hooks/adr-probe.sh" commit || exit 0
```

A missing script means the probe silently does nothing until `install.sh` runs,
instead of breaking the session.

## Consequences

The rule generalises beyond this hook: **anything registered in the
stow-managed `settings.json` that points at another stowed file must tolerate
that file being absent.** Config and payload arrive at different times, and
config arrives first.

A guard is not the same as a health check. A permanently missing script now
fails silently rather than loudly, so a genuinely broken deployment looks
identical to a working one that captures nothing. `doctor.sh` is the right
place to notice that, not the hook.
