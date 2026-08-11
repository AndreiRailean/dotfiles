---
type: ADR
status: rejected
date: 2026-08-09
summary: Editing domain-modeling in ~/.claude/plugins/cache to add proactive
  ADR writing is silently reverted by plugin auto-update.
---

# Editing skills in the plugin cache

## Context

`domain-modeling` almost does what is wanted: it has the gates, the format and
the ADR directory convention. It only declines to *write* — it is told to
"offer ADRs sparingly", and offering is what leaves the repo at one ADR in 88
commits. Changing "offer" to "write" is a two-word edit.

## What was tried

Editing `SKILL.md` and `ADR-FORMAT.md` in place under
`~/.claude/plugins/cache/claude-plugins-official/mattpocock-skills/`.

## How it failed

The marketplace entry in `settings.json` carries `"autoUpdate": true`. The next
plugin update overwrites the cache directory, reverting the edit with no
warning and no error. The system appears to work until it silently stops.

Two versions were already present on disk (`1.2.0` and `1.2.3`), so updates
were demonstrably happening.

## What would make it viable

Nothing while the plugin auto-updates. Setting `autoUpdate: false` would hold
the edit but freezes every other skill in the plugin, which is a worse trade.

The workable route is what was built instead: a separate `record-decision`
skill in the dotfiles-managed `~/.claude/skills/`, which nothing else writes
to. It duplicates the gates rather than sharing them, and that duplication is
the price of not being overwritten.
