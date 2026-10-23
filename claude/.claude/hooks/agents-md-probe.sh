#!/bin/sh
# agents-md-probe.sh — notice a repo whose AGENTS.md Claude Code will not load.
#
# WHY THIS FILE EXISTS: since 2.1.277 Claude Code loads AGENTS.md on its own,
# but only as a fallback — the default `instructionFiles` mode is
# "claude-md-or-agents-md". A CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md
# in the session directory or any directory above it, up to the repo root,
# switches the fallback off for the WHOLE session, and then no AGENTS.md is
# loaded unless a CLAUDE.md imports it. So the repo that loses its conventions
# is no longer the one with only AGENTS.md; it is the one that also has a
# CLAUDE.md that never mentions it — or a developer's gitignored
# CLAUDE.local.md that quietly turns the fallback off on one machine.
#
# That failure is silent from inside. The session cannot tell the difference
# between "this repo has no conventions" and "this repo has conventions I was
# never given", so it never thinks to look. Asking the question by hand has
# the same defect the missing file has — see the same reasoning in
# adr-probe.sh. So the question is hung off SessionStart, which fires on its
# own, once, in every repo.
#
# Like adr-probe.sh this script performs NO judgment and writes NO files. It
# emits a short probe and exits. Deciding what the pointer should say, and
# writing it, is the point-claude-at-agents-md skill's job.
#
# It must always exit 0. A SessionStart hook that fails is noise at the top of
# every single session.
#
# Usage: agents-md-probe.sh   (hook payload JSON on stdin)

set -u

payload=''
line=''
while IFS= read -r line || [ -n "$line" ]; do
  payload="$payload$line"
  line=''
done

# SessionStart runs in the project directory, but the payload carries `cwd`
# explicitly and that is the value Claude Code considers authoritative. Prefer
# it; fall back to PWD when the field is absent or unparseable.
cwd=$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

cd "$cwd" 2>/dev/null || exit 0

# Tracked files only. An AGENTS.md sitting in a gitignored vendor/ or plugin
# cache is not this repo's contract to fix, and node_modules would otherwise
# make this probe unboundedly slow.
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Is the native fallback off? Walk from the session directory up to the repo
# root, as Claude Code does, looking on disk rather than in git: CLAUDE.local.md
# is normally gitignored and switches the fallback off all the same. Verified
# against 2.1.308 — ~/.claude/CLAUDE.md, the global file, does not count.
fallback_off=0
d=$(pwd -P)
while :; do
  if [ -f "$d/CLAUDE.md" ] || [ -f "$d/.claude/CLAUDE.md" ] || [ -f "$d/CLAUDE.local.md" ]; then
    fallback_off=1
    break
  fi
  [ "$d" = "$root" ] || [ "$d" = / ] && break
  d=$(dirname "$d")
done
# With the fallback on, every AGENTS.md loads where a CLAUDE.md would.
[ "$fallback_off" -eq 1 ] || exit 0

cd "$root" 2>/dev/null || exit 0

missing=''
count=0
for agents in $(git ls-files -- '*AGENTS.md' 'AGENTS.md' 2>/dev/null); do
  # git ls-files is case-sensitive on the pattern but the checkout may not be;
  # confirm the basename really is AGENTS.md before acting on it.
  case "${agents##*/}" in
    AGENTS.md) ;;
    *) continue ;;
  esac
  [ -f "$agents" ] || continue

  dir="${agents%AGENTS.md}"
  claude="${dir}CLAUDE.md"

  # Present AND pointing at AGENTS.md. A CLAUDE.md that exists but never
  # mentions AGENTS.md is the more interesting failure, not a pass — the two
  # files then drift with nothing connecting them.
  if [ -f "$claude" ] && grep -q 'AGENTS\.md' "$claude" 2>/dev/null; then
    continue
  fi

  count=$((count + 1))
  # Cap the list. The probe is a pointer, not a report; the skill re-scans.
  [ "$count" -le 3 ] && missing="$missing ${dir:-./}"
done

[ "$count" -eq 0 ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "This repo has $count AGENTS.md file(s) that no sibling CLAUDE.md imports (${missing# }). This session has a CLAUDE.md (or CLAUDE.local.md), which switches off Claude Code's native AGENTS.md loading, so those conventions are NOT in your context and you are working from discovery rather than what the repo wrote down. Invoke the point-claude-at-agents-md skill to fix it, or read the AGENTS.md files yourself before relying on any assumption about this repo's conventions."

exit 0
