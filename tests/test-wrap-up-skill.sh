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
assert_contains "$body" "follow it instead of this one" "the hand-over replaces this skill, not adds to it"
# The probe reads the starting directory and the skill the current one, so a
# session can record here and hand over elsewhere.
handover_text="$(sed -n '/^## 0\./,/^## The one rule/p' "$SKILL")"
assert_contains "$handover_text" "ledger.sh open" "the hand-over still reads this ledger"

# PRs by author include other sessions'; a merge cannot be taken back.
assert_not_contains "$body" "gh pr list" "PRs come from the ledger, not from a search by author"
assert_contains "$body" "Merging is not a wrap-up step" "a wrap-up never merges on its own"

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

# A doubled return once drove the count to -1, so the next taken: read as 0
# and the item vanished from the wrap-up.
export CLAUDE_CODE_SESSION_ID=s3
sh "$L" taken 'branch a' >/dev/null
sh "$L" returned 'branch a' >/dev/null
sh "$L" returned 'branch a' >/dev/null
sh "$L" taken 'branch a (again)' >/dev/null
out="$(sh "$L" open 2>&1)"
assert_contains "$out" "open: branch a (again)" "a doubled return cannot hide a later taken:"
assert_contains "$out" "nothing open under that name" "the doubled return is reported"

# A name can end in "(1)". The key cuts it; what is printed must not, since
# the skill removes files by the path it reads here.
sh "$L" taken 'file /x/report (1)' >/dev/null
out="$(sh "$L" open 2>&1)"
assert_contains "$out" "open: file /x/report (1)" "an open item is printed as it was taken"
export CLAUDE_CODE_SESSION_ID=s1

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

  # A worktree nested under this one (.claude/worktrees/) is that worktree's.
  ( cd "$TMP/plain" && $G commit --quiet --allow-empty -m init &&
    $G worktree add --quiet .claude/worktrees/w >/dev/null 2>&1 )
  ( cd "$TMP/plain/.claude/worktrees/w" && exec sleep 31 ) &
  inner=$!
  sleep 0.2
  out="$(cd "$TMP/plain" && sh "$L" procs; :)"
  kill "$inner" 2>/dev/null
  assert_not_contains "$out" "sleep 31" "a process in a nested worktree is that worktree's"
fi

# ── the probe ─────────────────────────────────────────────────
probe() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" | LEDGER_SH="$L" sh "$PROBE"; }

out="$(probe s2 "$TMP/plain")"
assert_contains "$out" '"hookEventName":"SessionStart"' "the probe fires in a repo without its own wrap-up"
assert_contains "$out" "ledger.sh taken" "the probe says how to record"
assert_not_contains "$out" "open item" "a fresh session has nothing open"

out="$(probe s1 "$TMP/plain")"
assert_contains "$out" "already holds 3 open item(s)" "a resumed session is told what is open"

# A repo's own wrap-up is not its own ledger rule: andrei.md asks for a ledger
# only in the skill body, read at the end, and framestep keeps none.
out="$(probe s2 "$TMP/own/pkg")"
assert_contains "$out" "ledger.sh taken" "a repo wrap-up alone does not silence the probe"
printf 'Keep a ledger from your first action.\n' >"$TMP/own/CLAUDE.md"
out="$(probe s2 "$TMP/own/pkg")"
assert_eq "$out" "" "silent where the repo's always-loaded instructions ask for their own ledger"
# The word alone, with no wrap-up of the repo's own to read that ledger, is not.
mkdir -p "$TMP/word"
$G init --quiet "$TMP/word"
printf 'The general ledger lives in accounts/.\n' >"$TMP/word/CLAUDE.md"
out="$(probe s2 "$TMP/word")"
assert_contains "$out" "ledger.sh taken" "mentioning a ledger without a wrap-up of its own does not silence it"

out="$(printf '{"session_id":"s2","cwd":"%s"}' "$TMP/plain" | LEDGER_SH="$TMP/missing.sh" sh "$PROBE")"; rc=$?
assert_eq "$out$rc" "0" "silent, and exits 0, when the skill is not installed"

out="$( (cd "$TMP" && printf '%s' '{}' | CLAUDE_CODE_SESSION_ID='' LEDGER_SH="$L" sh "$PROBE") )"; rc=$?
assert_eq "$out$rc" "0" "silent, and exits 0, with no session ID anywhere"

# ── a /clear: new session ID, same claude process ─────────────
# No payload names the previous ID, so SessionEnd(clear) and the
# SessionStart(clear) after it meet through the claude PID they share.
export CLAUDE_PID=4242
end_() { printf '{"hook_event_name":"SessionEnd","session_id":"%s","reason":"%s","transcript_path":"%s"}' "$1" "$2" "$3" | LEDGER_SH="$L" sh "$PROBE"; }
start_() { printf '{"hook_event_name":"SessionStart","session_id":"%s","source":"%s","cwd":"%s"}' "$1" "$2" "$3" | LEDGER_SH="$L" sh "$PROBE"; }

CLAUDE_CODE_SESSION_ID=c1 sh "$L" taken 'branch feat/c (2026-10-25)' >/dev/null
CLAUDE_CODE_SESSION_ID=c1 sh "$L" taken 'server :4000' >/dev/null
CLAUDE_CODE_SESSION_ID=c1 sh "$L" returned 'server :4000' >/dev/null
CLAUDE_CODE_SESSION_ID=c1 sh "$L" reviewed 'r1' >/dev/null

out="$(end_ c1 clear /t/c1.jsonl)"
assert_eq "$out" "" "SessionEnd prints nothing"
out="$(start_ c2 clear "$TMP/plain")"
assert_contains "$out" "it was c1" "after /clear the probe names the old session ID"
assert_contains "$out" "1 open item(s) were carried" "and says what was carried"
assert_contains "$out" "/t/c1.jsonl" "and where the conversation before it is"
out="$(sh "$L" open "$TMP/state/claude/ledger/c2" 2>&1)"
assert_contains "$out" "open: branch feat/c (2026-10-25)" "an open item crosses the /clear as it was taken"
assert_not_contains "$out" "server :4000" "a returned one does not"
assert_contains "$out" "last reviewed: r1" "the review boundary crosses with it"
assert_contains "$out" "before /clear: c1 /t/c1.jsonl" "the new ledger names the old ID and transcript"
[ ! -e "$TMP/state/claude/ledger/cleared.4242" ] && pass "the handoff is consumed" || fail "the handoff is consumed"

# A second /clear keeps the first transcript in reach.
end_ c2 clear /t/c2.jsonl >/dev/null
start_ c3 clear "$TMP/plain" >/dev/null
out="$(sh "$L" open "$TMP/state/claude/ledger/c3" 2>&1)"
assert_contains "$out" "before /clear: c1 /t/c1.jsonl" "a chain of /clears keeps every transcript"
assert_contains "$out" "open: branch feat/c" "and the item"

# Only a /clear hands off.
end_ c3 prompt_input_exit /t/c3.jsonl >/dev/null
[ ! -e "$TMP/state/claude/ledger/cleared.4242" ] && pass "an ordinary exit leaves no handoff" || fail "an ordinary exit leaves no handoff"
out="$(start_ c4 startup "$TMP/plain")"
assert_not_contains "$out" "/clear" "a fresh start says nothing about a /clear"

# Another claude process's /clear is not this one's.
end_ c3 clear /t/c3.jsonl >/dev/null
out="$(CLAUDE_PID=4343 start_ c5 clear "$TMP/plain")"
assert_not_contains "$out" "it was c3" "a handoff from another claude process is not taken"
rm -f "$TMP/state/claude/ledger/cleared.4242"

# Where the repo keeps its own ledger the probe is otherwise silent, but its
# ledger is keyed by session ID too, so the old ID still has to be named.
CLAUDE_CODE_SESSION_ID=c5 sh "$L" taken 'branch feat/d' >/dev/null
end_ c5 clear /t/c5.jsonl >/dev/null
out="$(start_ c6 clear "$TMP/own")"
assert_contains "$out" "it was c5" "a repo with its own ledger still hears the old ID"
assert_not_contains "$out" "ledger.sh taken" "but not this ledger's request"
out="$(sh "$L" open "$TMP/state/claude/ledger/c6" 2>&1)"
assert_contains "$out" "open: branch feat/d" "and its items are still carried"

# Every note is valid JSON, whatever the path holds.
end_ c6 clear '/t/my\tdir/c\"6.jsonl' >/dev/null
out="$(start_ c7 clear "$TMP/plain")"
printf '%s' "$out" | jq -e . >/dev/null 2>&1 && pass "the /clear note is valid JSON" || fail "the /clear note is valid JSON: $out"
assert_contains "$out" "1 open item(s) were carried" "a tab in the transcript path does not shift the count"
assert_contains "$(cat "$TMP/state/claude/ledger/c7")" 'c"6.jsonl' "and a quote in it is kept in the ledger"
end_ c7 clear '' >/dev/null
out="$(start_ c8 clear "$TMP/plain")"
assert_contains "$out" "1 open item(s) were carried" "nor does an empty transcript path"
assert_not_contains "$out" "is at" "which is not named"

# The old ID hands its items over, so a resume of it does not claim them too.
out="$(sh "$L" open "$TMP/state/claude/ledger/c7" 2>&1)"
assert_contains "$out" "0 open" "the cleared ledger no longer holds what it handed on"
assert_contains "$out" "after /clear: c8" "and says where it went"

# A review after the /clear read those transcripts; the next one starts there.
CLAUDE_CODE_SESSION_ID=c8 sh "$L" reviewed 'r2' >/dev/null
out="$(sh "$L" open "$TMP/state/claude/ledger/c8" 2>&1)"
assert_contains "$out" "last reviewed: r2" "a review after a /clear moves the boundary"
assert_not_contains "$out" "before /clear" "and drops the transcripts it covered"
end_ c8 clear /t/c8.jsonl >/dev/null
start_ c9 clear "$TMP/plain" >/dev/null
out="$(sh "$L" open "$TMP/state/claude/ledger/c9" 2>&1)"
assert_contains "$out" "last reviewed: r2" "the boundary crosses the next /clear"
assert_contains "$out" "before /clear: c8 /t/c8.jsonl" "followed by only the transcript after it"
assert_not_contains "$out" "/t/c1.jsonl" "not the reviewed ones"

# A handoff left by a /clear that never started is not this one's: PIDs repeat.
end_ c9 clear /t/c9.jsonl >/dev/null
touch -t 202001010000 "$TMP/state/claude/ledger/cleared.4242"
out="$(start_ c10 clear "$TMP/plain")"
assert_not_contains "$out" "it was c9" "a stale handoff is not taken"
assert_contains "$out" "no handoff" "and a /clear with none says so, since its ledger reads 0 open"
printf '%s' "$out" | jq -e . >/dev/null 2>&1 && pass "that note is valid JSON" || fail "that note is valid JSON: $out"
unset CLAUDE_PID

# Without CLAUDE_PID (older claude), the nearest ancestor named claude links the two.
mkdir -p "$TMP/bin"
ln -s "$(command -v sh)" "$TMP/bin/claude"
out="$(LEDGER_SH="$L" PROBE="$PROBE" "$TMP/bin/claude" -c '
  printf "%s" "{\"hook_event_name\":\"SessionEnd\",\"session_id\":\"c9\",\"reason\":\"clear\",\"transcript_path\":\"/t/p.jsonl\"}" | sh "$PROBE"
  printf "%s" "{\"hook_event_name\":\"SessionStart\",\"session_id\":\"p2\",\"source\":\"clear\",\"cwd\":\"/\"}" | sh "$PROBE"
  :')"
assert_contains "$out" "it was c9" "without CLAUDE_PID the claude ancestor carries the handoff"

# The recipe step 5 gives reads past a torn line and keeps only what the user said.
tr_="$TMP/t.jsonl"
{
  printf '%s\n' '{"type":"user","message":{"content":"first correction"}}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","content":"noise"}]}}'
  printf '%s\n' '{"type":"user","isMeta":true,"message":{"content":"meta noise"}}'
  printf '%s\n' '{"type":"user","isCompactSummary":true,"message":{"content":"summary noise"}}'
  printf '%s\n' '{"type":"user","message":{"content":"<task-notification>noise</task-notification>"}}'
  printf '%s\n' '{"type":"user","message":{"cont{"type":"assistant"}'
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"second correction"}]}}'
} >"$tr_"
recipe="$(printf '%s\n' "$body" | sed -n 's/^\(jq .*\) <transcript>$/\1/p')"
out="$(eval "$recipe \"\$tr_\"" 2>&1)"
assert_contains "$out" "second correction" "the transcript recipe reads past a torn line"
assert_contains "$out" "first correction" "and keeps the user's words"
assert_not_contains "$out" "noise" "and drops tool results, meta, summaries and notifications"

settings="$(cat "$REPO/claude/.claude/settings.json")"
assert_contains "$settings" 'hooks/ledger-probe.sh' "settings.json registers the probe"
ends="$(jq -r '.hooks.SessionEnd[].hooks[].command' "$REPO/claude/.claude/settings.json" 2>/dev/null)"
assert_contains "$ends" 'ledger-probe.sh' "and runs it at SessionEnd, for the /clear handoff"

# The user's rule: /clear is safe only after a wrap-up.
assert_contains "$desc" "before a /clear" "description triggers before a /clear"
assert_contains "$body" "/clear: safe | not yet" "the report says whether a /clear is safe"
assert_contains "$body" '`not captured:` is empty' "and a finding still waiting on the user makes it not yet"
assert_contains "$body" "Before a \`/clear\`, end its report with this file's" "the hand-over keeps the /clear verdict"

finish
