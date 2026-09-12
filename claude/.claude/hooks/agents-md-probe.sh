#!/bin/sh
# agents-md-probe.sh — notice a repo whose AGENTS.md Claude Code cannot read.
#
# WHY THIS FILE EXISTS: Claude Code loads CLAUDE.md. It does not load
# AGENTS.md — as of 2.1.269 the only place the CLI mentions that filename is
# the `/import` path that migrates a Codex project *into* a CLAUDE.md. A repo
# that writes only AGENTS.md therefore hands Claude nothing, and every session
# rediscovers the conventions from scratch.
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
  "This repo has $count AGENTS.md file(s) that no sibling CLAUDE.md imports (${missing# }). Claude Code does not read AGENTS.md, so those conventions are NOT in your context and you are working from discovery rather than what the repo wrote down. Invoke the point-claude-at-agents-md skill to fix it, or read the AGENTS.md files yourself before relying on any assumption about this repo's conventions."

exit 0
