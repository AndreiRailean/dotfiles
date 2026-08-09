#!/bin/sh
# adr-probe.sh emits a probe question when something ADR-worthy may have
# happened, and stays silent otherwise. It runs on EVERY Bash tool call, so
# "stays silent and exits 0" is the property that matters most — a probe that
# errors or chatters would be noticed on every command the agent runs.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/adr-probe.sh"

[ -x "$PROBE" ] && pass "adr-probe.sh exists and is executable" \
  || fail "adr-probe.sh exists and is executable"

# ── commit mode ───────────────────────────────────────────────
# Fires on a successful git commit.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"[main abc1234] x\n 1 file changed"}}' | sh "$PROBE" commit)"
assert_contains "$out" 'hookSpecificOutput' "commit mode emits hookSpecificOutput"
assert_contains "$out" 'PostToolUse' "commit mode names the PostToolUse event"
assert_contains "$out" 'record-decision' "commit mode names the skill to invoke"

# Silent on any other Bash command. This is the common case by a wide margin.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":{"stdout":"a b c"}}' | sh "$PROBE" commit)"
assert_eq "$out" "" "commit mode is silent on a non-commit command"

# Silent when the commit did nothing. An empty commit is not a decision.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"nothing to commit, working tree clean"}}' | sh "$PROBE" commit)"
assert_eq "$out" "" "commit mode is silent when nothing was committed"

# A commit can fail for reasons other than an empty index — a pre-commit hook
# rejection, a signing failure, a conflict. Enumerating git's failure modes is
# whack-a-mole, so the probe must not assert that anything landed.
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"tool_response":{"stdout":"","stderr":"error: failed to push some refs"}}' | sh "$PROBE" commit)"
assert_contains "$out" 'attempted' "commit mode does not claim a failed commit landed"
assert_not_contains "$out" 'just landed' "commit mode never asserts a commit landed"

# ── subagent mode ─────────────────────────────────────────────
# Write-capable agents are told to record it themselves.
out="$(printf '%s' '{"agent_type":"general-purpose","agent_id":"a1"}' | sh "$PROBE" subagent)"
assert_contains "$out" 'SubagentStop' "subagent mode names the SubagentStop event"
assert_contains "$out" 'record-decision' "write-capable agent is told to invoke the skill"

# Explore and Plan are defined as all tools EXCEPT Write, so telling them to
# write a file sends them into a wall. They report back as text instead.
out="$(printf '%s' '{"agent_type":"Explore","agent_id":"a2"}' | sh "$PROBE" subagent)"
assert_contains "$out" 'final message' "write-less agent is told to report as text"
assert_not_contains "$out" 'invoke record-decision' "write-less agent is not told to write"

# ── never disruptive ──────────────────────────────────────────
# Unknown mode, empty stdin, garbage stdin: all silent, all exit 0.
printf '' | sh "$PROBE" commit >/dev/null 2>&1
assert_eq "$?" "0" "empty stdin exits 0"
printf 'not json at all' | sh "$PROBE" subagent >/dev/null 2>&1
assert_eq "$?" "0" "malformed stdin exits 0"
printf '{}' | sh "$PROBE" bogus-mode >/dev/null 2>&1
assert_eq "$?" "0" "unknown mode exits 0"

finish
