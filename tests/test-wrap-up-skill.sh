#!/bin/sh
# The global wrap-up skill, its ledger script and its session-start probe.
#
# A personal skill shadows a project skill of the same name, so this one runs
# even in telik, andrei.md and framestep, which wrote their own. It hands over
# to the repo's file when `ledger.sh project-skill` finds one, and the probe
# stays quiet there. Those two must agree, and the ledger's counting must be
# right, since a wrap-up returns exactly what the ledger says is open.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
DIR="$REPO/claude/.claude/skills/wrap-up"
SKILL="$DIR/SKILL.md"
L="$DIR/ledger.sh"
PROBE="$REPO/claude/.claude/hooks/ledger-probe.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
export XDG_STATE_HOME="$TMP/state"
G="git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false"

# ── the skill ─────────────────────────────────────────────────
[ -f "$SKILL" ] && pass "SKILL.md exists" || fail "SKILL.md exists"
body="$(cat "$SKILL" 2>/dev/null)"
assert_contains "$body" "name: wrap-up" "skill declares its name"
# "I'm done" is the trigger as often as /wrap-up is.
assert_not_contains "$body" "disable-model-invocation" "skill is model-invocable"

desc="$(sed -n 's/^description: //p' "$SKILL")"
assert_contains "$desc" "asks for a wrap-up" "description names the explicit trigger"
assert_contains "$desc" "handed off" "description names the hand-off trigger"
assert_contains "$desc" "before saying a task is finished" "description names the done trigger"

# The loader replaces $0..$9 and $ARGUMENTS in a skill body with the
# invocation's words; telik's inline awk read "/wrap-up hopefully for the last
# time" as its fields. Code that needs them lives in ledger.sh.
if grep -nE '\$[0-9]|\$ARGUMENTS' "$SKILL" >/dev/null; then
  fail "skill body has no loader-substituted \$0..\$9 or \$ARGUMENTS"
else
  pass "skill body has no loader-substituted \$0..\$9 or \$ARGUMENTS"
fi
assert_contains "$body" 'sh ${CLAUDE_SKILL_DIR}/ledger.sh' "skill reaches its script through CLAUDE_SKILL_DIR"

# The hand-over has to be read before any step acts.
handover=$(grep -n 'ledger.sh project-skill' "$SKILL" | head -1 | cut -d: -f1)
first_step=$(grep -n '^## 1\.' "$SKILL" | cut -d: -f1)
[ -n "$handover" ] && [ -n "$first_step" ] && [ "$handover" -lt "$first_step" ] \
  && pass "the repo's own wrap-up is checked before step 1" \
  || fail "the repo's own wrap-up is checked before step 1"
assert_contains "$body" "stop reading here" "the hand-over replaces this skill, not adds to it"

assert_contains "$body" "Return what is yours. Report everything else." "body states the one rule"
assert_contains "$body" "read unfiltered" "tree check is read unfiltered"
assert_contains "$body" "--prune" "branches are checked after a prune"
assert_contains "$body" "is never part of a" "git clean -X is ruled out"

# ── ledger.sh: counting ───────────────────────────────────────
export CLAUDE_CODE_SESSION_ID=s1
f="$(sh "$L" path)"
assert_eq "$f" "$TMP/state/claude/ledger/s1" "ledger is keyed by session under XDG state"

sh "$L" taken 'branch feat/x (2026-10-24)' >/dev/null
sh "$L" taken 'server :5173' >/dev/null
sh "$L" taken 'file /tmp/a (copy)/b' >/dev/null
sh "$L" returned 'branch feat/x (deleted after #12)' >/dev/null
out="$(sh "$L" open 2>&1)"
assert_not_contains "$out" "open: branch feat/x" "a returned item matches despite a different note"
assert_contains "$out" "open: server :5173" "an unreturned item is open"
assert_contains "$out" "open: file /tmp/a (copy)/b" "only a trailing note is cut"
assert_contains "$out" "2 open" "the count is printed"

sh "$L" taken 'branch feat/x (again)' >/dev/null
out="$(sh "$L" open 2>&1)"
assert_contains "$out" "open: branch feat/x" "an item taken again after its return is open again"

sh "$L" reviewed 'abc123' >/dev/null
echo 'stray words' >>"$f"
out="$(sh "$L" open 2>&1)"
assert_contains "$out" "last reviewed: abc123" "the last review boundary is printed"
assert_contains "$out" "is not taken:, returned: or reviewed:" "an unreadable line is reported, not dropped"

out="$(CLAUDE_CODE_SESSION_ID='' sh "$L" taken 'branch y' 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "refuses to write without a session ID" || fail "refuses to write without a session ID"

# ── ledger.sh: which repos have their own wrap-up ─────────────
mkdir -p "$TMP/own/.claude/skills/wrap-up" "$TMP/own/pkg/deep"
$G init --quiet "$TMP/own"
echo '# repo wrap-up' >"$TMP/own/.claude/skills/wrap-up/SKILL.md"
out="$(sh "$L" project-skill "$TMP/own")"
assert_contains "$out" "/own/.claude/skills/wrap-up/SKILL.md" "finds a repo's own wrap-up at its root"
out="$(sh "$L" project-skill "$TMP/own/pkg/deep")"
assert_contains "$out" "/own/.claude/skills/wrap-up/SKILL.md" "finds it from a subdirectory"

mkdir -p "$TMP/plain"
$G init --quiet "$TMP/plain"
sh "$L" project-skill "$TMP/plain" >/dev/null; rc=$?
assert_eq "$rc" "1" "nothing to hand over to in a repo without one"

# Above a repo's root is not that repo's.
mkdir -p "$TMP/outer/.claude/skills/wrap-up" "$TMP/outer/inner"
echo '# outer' >"$TMP/outer/.claude/skills/wrap-up/SKILL.md"
$G init --quiet "$TMP/outer/inner"
sh "$L" project-skill "$TMP/outer/inner" >/dev/null; rc=$?
assert_eq "$rc" "1" "the walk stops at the repo root"

# Outside a repo, the walk would reach ~/.claude/skills/wrap-up, which is
# this skill, so only the directory itself counts, and never this skill.
mkdir -p "$TMP/home/.claude/skills/wrap-up" "$TMP/home/work"
ln -s "$SKILL" "$TMP/home/.claude/skills/wrap-up/SKILL.md"
sh "$L" project-skill "$TMP/home" >/dev/null; rc=$?
assert_eq "$rc" "1" "this skill, reached through a link, is never the repo's own"
mkdir -p "$TMP/loose/.claude/skills/wrap-up" "$TMP/loose/work"
echo '# not this directory'"'"'s' >"$TMP/loose/.claude/skills/wrap-up/SKILL.md"
sh "$L" project-skill "$TMP/loose/work" >/dev/null; rc=$?
assert_eq "$rc" "1" "outside a repo there is no walk upwards"

# ── ledger.sh: processes left in the worktree ─────────────────
if [ -d /proc/self ]; then
  ( cd "$TMP/plain" && exec sleep 30 ) &
  stray=$!
  sleep 0.2
  # Run from inside the worktree, as a session does, so the script's own
  # subshells and its parent shell are in it too and have to be left out. The
  # trailing `:` stops the shell exec'ing sh in place of that parent.
  out="$(cd "$TMP/plain" && sh "$L" procs; :)"
  kill "$stray" 2>/dev/null
  assert_contains "$out" "sleep 30" "a process left running in the worktree is listed"
  assert_not_contains "$out" "ledger.sh" "the script's own processes are not"
  assert_not_contains "$out" "test-wrap-up-skill" "nor the shell that ran it"
fi

# ── the probe ─────────────────────────────────────────────────
probe() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" | LEDGER_SH="$L" sh "$PROBE"; }

out="$(probe s2 "$TMP/plain")"
assert_contains "$out" '"hookEventName":"SessionStart"' "the probe fires in a repo without its own wrap-up"
assert_contains "$out" "ledger.sh taken" "the probe says how to record"
assert_not_contains "$out" "open item" "a fresh session has nothing open"

out="$(probe s1 "$TMP/plain")"
assert_contains "$out" "already holds 3 open item(s)" "a resumed session is told what is open"

out="$(probe s2 "$TMP/own/pkg")"
assert_eq "$out" "" "the probe is silent where the repo has its own wrap-up"

out="$(printf '{"session_id":"s2","cwd":"%s"}' "$TMP/plain" | LEDGER_SH="$TMP/missing.sh" sh "$PROBE")"; rc=$?
assert_eq "$out$rc" "0" "silent, and exits 0, when the skill is not installed"

out="$( (cd "$TMP" && printf '%s' '{}' | CLAUDE_CODE_SESSION_ID='' LEDGER_SH="$L" sh "$PROBE") )"; rc=$?
assert_eq "$out$rc" "0" "silent, and exits 0, with no session ID anywhere"

settings="$(cat "$REPO/claude/.claude/settings.json")"
assert_contains "$settings" 'hooks/ledger-probe.sh' "settings.json registers the probe"

finish
