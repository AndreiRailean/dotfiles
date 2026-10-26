---
type: ADR
status: accepted
date: 2026-10-26
summary: The herdr auto-layout daemon is removed and herdr becomes an optional
  tool; a new worktree opens as herdr makes it, and Claude Code is started by
  hand.
---

# Drop the herdr auto-layout daemon

## Context

herdr has no hook that runs a command when a worktree is created. To get one,
`herdr-autolayout` subscribed to the socket API's event stream and arranged
each new worktree workspace: it split the tab in two, typed `claude` into the
left pane, and named the tab. It ran as a systemd user unit on Linux and a
generated launchd agent on macOS. `doctor.sh` checked that it was running, and
`prefix+shift+L` ran it by hand.

The right-hand pane was being closed almost every time, so the split was
turned off (#35). After that, the daemon only named a tab and typed one word,
and it still cost:

- a service on every machine, set up by two different service managers;
- about 500 lines of Python, most of them spent making typed text survive a
  slow shell start;
- a retest after every herdr upgrade. The daemon relied on two API behaviours
  herdr doesn't document: `workspace_created` is delivered on a subscription
  the schema says can't carry it, and `events.wait` rejects workspace matches
  it advertises. If either changed, layouts would stop silently.

herdr is also only wanted on some machines. The daemon, its doctor checks and
its retest made herdr part of every install.

## Decision

Remove the daemon, its units, the `prefix+shift+L` binding, the doctor checks
and the retest box in `config.toml`. A new worktree opens with one shell, and
Claude Code is started by typing `claude`.

herdr moves to `update.sh`'s optional tools: `./update.sh --add herdr` puts it
on a machine, and on macOS that goes through Homebrew. Its `config.toml` is
still stowed everywhere, since it's harmless without herdr.

`install.sh` retires an existing install: it stops the systemd unit, or
unloads and deletes the launchd plist. `.config/systemd` joins
`RETIRED_ROOTS`, so the unit's links, including the absolute one that
`systemctl enable` made, are pruned like any other dead link.

## Consequences

- Bringing back automatic startup means bringing back a daemon, unless herdr
  gains a worktree hook. Check for one (`herdr --default-config`) first.
- [20261026-update-sh-owns-tool-acquisition](20261026-update-sh-owns-tool-acquisition.md)
  gave herdr's retest as one reason upgrades are a deliberate `--apply`. That
  reason is gone, but the rule stands: an upgrade can still change behaviour,
  and `install.sh` stays safe to re-run.
- On macOS, `--add herdr` installs it but doesn't start its brew service.
  The next `install.sh` run does that, and `update.sh` says so.
