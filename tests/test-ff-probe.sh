#!/bin/sh
# ff-probe.sh asks for a fast-forward of the main checkout after a PR merge.
# It runs on EVERY Bash tool call, so silence is the property that matters:
# during development it fired three times in an hour on documents ABOUT the
# rule — a heredoc, a commit message and an issue body — and each false firing
# teaches the reader to ignore the real one.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/ff-probe.sh"

[ -x "$PROBE" ] && pass "ff-probe.sh exists and is executable" \
  || fail "ff-probe.sh exists and is executable"

run() { printf '%s' "$1" | sh "$PROBE" merge; }

# ── it fires on an actual merge ───────────────────────────────
# gh prints NOTHING when stdout is not a terminal, which is the normal case
# under the agent. An earlier version demanded gh's confirmation and missed a
# real merge because of it, so the bare case is the important one.
out="$(run '{"tool_input":{"command":"gh pr merge 76 --squash"},"tool_response":{"stdout":""}}')"
assert_contains "$out" 'hookSpecificOutput' "a silent merge still emits a probe"
assert_contains "$out" 'PostToolUse' "the probe names the PostToolUse event"
assert_contains "$out" 'ff-only' "the probe names the safe merge mode"
assert_contains "$out" 'git -C' "the probe says not to cd"

out="$(run '{"tool_input":{"command":"git fetch && gh pr merge 76"},"tool_response":{"stdout":""}}')"
assert_contains "$out" 'hookSpecificOutput' "a merge chained after another command fires"

# ── it is silent on documents ABOUT the rule ──────────────────
# All three of these fired during development. Prose puts a space before the
# phrase; a shell puts the start of the command or a separator there.
out="$(run '{"tool_input":{"command":"cat >> CLAUDE.md <<EOF\nafter gh pr merge, fast-forward main\nEOF"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when a heredoc writes the rule into a file"

out="$(run '{"tool_input":{"command":"git commit -m \"note: gh pr merge prints nothing off a tty\""},"tool_response":{"stdout":"1 file changed"}}')"
assert_eq "$out" "" "silent when a commit message quotes the command"

out="$(run '{"tool_input":{"command":"gh issue comment 5 --body \"run gh pr merge then ff\""},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when an issue body describes the command"

# tool_response carries command OUTPUT, so a grep over a repo that mentions a
# past merge must not fire. This is adr-probe.sh's lesson, measured there at
# six false positives in one session.
out="$(run '{"tool_input":{"command":"grep -rn merged docs/"},"tool_response":{"stdout":"docs/x.md: Merged pull request #12"}}')"
assert_eq "$out" "" "silent when only the OUTPUT mentions a merge"

# ── it is silent when no merge happened ───────────────────────
out="$(run '{"tool_input":{"command":"gh pr merge 70"},"tool_response":{"stderr":"Pull request #70 is not mergeable"}}')"
assert_eq "$out" "" "silent when the merge was refused"

# --auto queues a merge for later; there is nothing to fast-forward to yet.
out="$(run '{"tool_input":{"command":"gh pr merge 71 --auto"},"tool_response":{"stderr":"Pull request #71 will be automatically merged"}}')"
assert_eq "$out" "" "silent when --auto only queues the merge"

out="$(run '{"tool_input":{"command":"git status"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent on an unrelated command"

# ── it never disrupts a session ───────────────────────────────
printf '%s' '{"tool_input":{"command":"gh pr merge 1"}}' | sh "$PROBE" merge >/dev/null 2>&1
assert_eq "$?" "0" "exits 0 on a merge"
printf 'not json at all' | sh "$PROBE" merge >/dev/null 2>&1
assert_eq "$?" "0" "exits 0 on a payload that is not JSON"
printf '%s' '{}' | sh "$PROBE" >/dev/null 2>&1
assert_eq "$?" "0" "exits 0 with no mode argument"
printf '%s' '{}' | sh "$PROBE" bogus >/dev/null 2>&1
assert_eq "$?" "0" "exits 0 on an unknown mode"

# A multi-line payload with no trailing newline: the read loop is the only
# thing between that and a silently missed match.
out="$(printf '{\n  "tool_input": {\n    "command": "gh pr merge 9"\n  }\n}')"
out="$(printf '%s' "$out" | sh "$PROBE" merge)"
assert_contains "$out" 'ff-only' "multi-line payload without a trailing newline still matches"

finish
