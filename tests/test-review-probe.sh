#!/bin/sh
# review-probe.sh asks for a fresh review after a PR is opened. It runs on
# EVERY Bash tool call, so silence is the property that matters: a probe that
# fires on prose about the command teaches the reader to ignore the real one.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/review-probe.sh"

[ -x "$PROBE" ] && pass "review-probe.sh exists and is executable" \
  || fail "review-probe.sh exists and is executable"

grep -q 'review-probe.sh' "$REPO/claude/.claude/settings.json" \
  && pass "settings.json registers review-probe.sh" \
  || fail "settings.json registers review-probe.sh"

EMPTY="$(mktemp -d)"
run() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$EMPTY" sh "$PROBE"; }

# ── it fires on an opened PR ──────────────────────────────────
out="$(run '{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"https://github.com/a/b/pull/9"}}')"
assert_contains "$out" 'hookSpecificOutput' "an opened PR emits a probe"
assert_contains "$out" 'PostToolUse' "the probe names the PostToolUse event"
assert_contains "$out" 'fails silently' "the probe gives the review its brief"

out="$(run '{"tool_input":{"command":"git push && gh pr create --fill"},"tool_response":{"stdout":""}}')"
assert_contains "$out" 'hookSpecificOutput' "a create chained after a push fires"

# ── it is silent on everything else ───────────────────────────
out="$(run '{"tool_input":{"command":"cat >> x.md <<EOF\nafter gh pr create, review\nEOF"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when a heredoc writes about the command"

out="$(run '{"tool_input":{"command":"git commit -m \"run gh pr create first\""},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when a commit message quotes the command"

out="$(run '{"tool_input":{"command":"grep -r review docs"},"tool_response":{"stdout":"gh pr create"}}')"
assert_eq "$out" "" "silent when only the output mentions the command"

out="$(run '{"tool_input":{"command":"gh pr merge 9 --squash"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent on a merge"

out="$(run '{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"a pull request for branch x already exists"}}')"
assert_eq "$out" "" "silent when the create failed"

# ── it defers to a repo's own probe ───────────────────────────
OWN="$(mktemp -d)"
mkdir -p "$OWN/.claude/hooks" && : >"$OWN/.claude/hooks/review-probe.sh"
out="$(printf '%s' '{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":""}}' | CLAUDE_PROJECT_DIR="$OWN" sh "$PROBE")"
assert_eq "$out" "" "silent in a repo that ships its own review-probe.sh"
rm -rf "$EMPTY" "$OWN"

finish
