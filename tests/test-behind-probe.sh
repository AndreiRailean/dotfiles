#!/bin/sh
# behind-probe.sh reports, at session start, that the world moved: this
# worktree or the main checkout is behind the default branch. It exists
# because a session planning against a stale tree does confident, wasted work
# — measured once as three issues filed for work already merged.
#
# Hermetic: every repo here is a local bare "origin" in a temp dir, so nothing
# touches the network.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PROBE="$REPO/claude/.claude/hooks/behind-probe.sh"

[ -x "$PROBE" ] && pass "behind-probe.sh exists and is executable" \
  || fail "behind-probe.sh exists and is executable"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM

G="git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false"
run_in() { ( cd "$1" && printf '%s' '{}' | sh "$PROBE" ); }

# origin, a clone that will fall behind, and a second clone to advance it.
$G init --quiet --bare "$TMP/origin.git"
$G clone --quiet "$TMP/origin.git" "$TMP/work" 2>/dev/null
( cd "$TMP/work" && echo one > a && $G add a && $G commit --quiet -m one && $G push --quiet -u origin main ) 2>/dev/null
$G clone --quiet "$TMP/origin.git" "$TMP/other" 2>/dev/null

# ── in sync ───────────────────────────────────────────────────
out="$(run_in "$TMP/work")"
assert_eq "$out" "" "silent when the worktree is level with origin"

# ── behind ────────────────────────────────────────────────────
( cd "$TMP/other" && echo two > b && $G add b && $G commit --quiet -m two && $G push --quiet origin main ) 2>/dev/null
out="$(run_in "$TMP/work")"
assert_contains "$out" 'hookSpecificOutput' "behind emits a probe"
assert_contains "$out" 'SessionStart' "the probe names the SessionStart event"
assert_contains "$out" '1 commit' "the probe counts the commits it is behind"
assert_contains "$out" 'origin/main' "the probe names the branch it compared against"

# It must FETCH. Comparing against a stale remote ref reports "up to date" in
# exactly the case this exists to catch, so a probe that skipped the fetch
# would have stayed silent above.
assert_contains "$out" 'landed work' "the probe says what being behind means"

# ── a linked worktree reports the MAIN checkout too ───────────
# ff-probe.sh covers merges a session performs; this covers a merge done in
# another worktree or the web UI, which leaves the main checkout behind with
# nothing to notice.
( cd "$TMP/work" && $G worktree add --quiet -b side "$TMP/side" ) 2>/dev/null
out="$(run_in "$TMP/side")"
assert_contains "$out" 'main checkout' "a linked worktree reports the main checkout being behind"
assert_contains "$out" 'CLAUDE.md' "it points at the rule rather than acting"

# From the main checkout itself there is no second path to mention.
( cd "$TMP/work" && $G merge --quiet --ff-only origin/main ) 2>/dev/null
out="$(run_in "$TMP/side")"
assert_not_contains "$out" 'main checkout' "no main-checkout line once it is level"

# ── it never disrupts a session ───────────────────────────────
mkdir -p "$TMP/plain"
run_in "$TMP/plain" >/dev/null 2>&1
assert_eq "$?" "0" "exits 0 outside a git repository"
out="$(run_in "$TMP/plain")"
assert_eq "$out" "" "silent outside a git repository"

$G init --quiet "$TMP/noremote"
out="$(run_in "$TMP/noremote")"
assert_eq "$out" "" "silent in a repository with no origin"

finish
