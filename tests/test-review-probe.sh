#!/bin/sh
# review-probe.sh asks for a fresh review after a PR is opened. It runs on
# EVERY Bash tool call, so silence is the property that matters: a probe that
# fires on prose about the command teaches the reader to ignore the real one.
# It fires on the outcome (a PR URL, or output captured in $(...)), not on
# the spelling, which a review showed missed the commonest form.
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
URL='"https://github.com/a/b/pull/9"'

# ── it fires on an opened PR, in any spelling ─────────────────
out="$(run '{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":'"$URL"'}}')"
assert_contains "$out" 'hookSpecificOutput' "an opened PR emits a probe"
assert_contains "$out" 'PostToolUse' "the probe names the PostToolUse event"
assert_contains "$out" 'fails silently' "the probe gives the review its brief"

for c in 'git push && gh pr create --fill' 'git push || gh pr create --fill' \
  'GH_REPO=a/b gh pr create --fill' 'gh -R a/b pr create --fill' \
  'bash -c \"gh pr create --fill\"' 'gh pr create --body \"the already exists case\"'; do
  out="$(run '{"tool_input":{"command":"'"$c"'"},"tool_response":{"stdout":'"$URL"'}}')"
  assert_contains "$out" 'hookSpecificOutput' "fires on: $c"
done

out="$(run '{"tool_input":{"command":"n=$(gh pr create --fill | grep -o [0-9]*$)"},"tool_response":{"stdout":""}}')"
assert_contains "$out" 'hookSpecificOutput' "fires when the URL is captured in \$(...)"

# ── it is silent on prose and on creates that opened nothing ──
out="$(run '{"tool_input":{"command":"cat >> x.md <<EOF\nafter gh pr create, review\nEOF"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when a heredoc writes about the command"

out="$(run '{"tool_input":{"command":"cat >> x.md <<EOF\ngh pr create opens a PR\nEOF"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent when a heredoc line starts with the command"

out="$(run '{"tool_input":{"command":"git commit -m \"docs; gh pr create now probes\""},"tool_response":{"stdout":"1 file changed"}}')"
assert_eq "$out" "" "silent when a commit message quotes the command"

out="$(run '{"tool_input":{"command":"grep -r review docs"},"tool_response":{"stdout":"gh pr create https://github.com/a/b/pull/9"}}')"
assert_eq "$out" "" "silent when only the output mentions the command"

out="$(run '{"tool_input":{"command":"gh pr merge 9 --squash"},"tool_response":{"stdout":""}}')"
assert_eq "$out" "" "silent on a merge"

out="$(run '{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":"a pull request for branch x already exists"}}')"
assert_eq "$out" "" "silent when the create failed"

# ── it defers to a repo's own probe, where that one will speak ─
OWN="$(mktemp -d)"
mkdir -p "$OWN/.claude/hooks" && : >"$OWN/.claude/hooks/review-probe.sh"
own() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$OWN" sh "$PROBE"; }
CREATE='{"tool_input":{"command":"gh pr create --fill"},"tool_response":{"stdout":'"$URL"'}}'

out="$(own "$CREATE")"
assert_contains "$out" 'hookSpecificOutput' "fires when the repo's probe exists but is not registered"

printf '{"hooks":{"PostToolUse":[{"hooks":[{"command":"sh review-probe.sh"}]}]}}' >"$OWN/.claude/settings.json"
out="$(own "$CREATE")"
assert_eq "$out" "" "silent in a repo that registers its own review-probe.sh"

out="$(own '{"tool_input":{"command":"cd ../other && gh pr create --fill"},"tool_response":{"stdout":'"$URL"'}}')"
assert_contains "$out" 'hookSpecificOutput' "fires when a cd may take the PR to another repo"
rm -rf "$EMPTY" "$OWN"

finish
