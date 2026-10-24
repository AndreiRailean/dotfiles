#!/bin/sh
# ledger-probe.sh — at session start, ask for the ledger the wrap-up reads.
#
# WHY THIS FILE EXISTS: the wrap-up skill returns only what the session's
# ledger names, and the ledger has to be written while the session works,
# from its first branch or server. A skill body loads only when it is invoked,
# which for a wrap-up is the end, after everything worth recording has
# happened. So the request is hung off SessionStart, which fires on its own,
# once, as adr-probe.sh and agents-md-probe.sh hang theirs off events.
#
# It is silent only where the repo asks for a ledger of its own from an
# always-loaded file (telik's CLAUDE.md names .bin/ledger.<session id>), since
# two ledger rules in one context compete; ledger.sh repo-ledger makes that
# call. A repo with its own wrap-up and no such line still gets the request:
# a first version stayed quiet wherever a repo had a wrap-up, and in andrei.md
# (ledger asked for only in the skill body, read at the end) and framestep (no
# ledger) no session was ever asked for one. The skill's hand-over reads this
# ledger as well as the repo's, so items recorded here are never lost to it.
#
# On a resume or after a compaction SessionStart fires again with the same
# session ID; the probe then says how many items are already open, since the
# conversation that recorded them may no longer be in context. A /clear starts
# a new session ID, and with it an empty ledger: what the old ID recorded is
# out of this one's count, a known gap.
#
# It writes NO files: ledger.sh creates the ledger on the first line taken.
# It must always exit 0. A SessionStart hook that fails is noise at the top of
# every session.
#
# Usage: ledger-probe.sh   (SessionStart hook payload JSON on stdin)

set -u

payload=''
line=''
while IFS= read -r line || [ -n "$line" ]; do
  payload="$payload$line"
  line=''
done

field() {
  printf '%s' "$payload" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p"
}

ledger="${LEDGER_SH:-$HOME/.claude/skills/wrap-up/ledger.sh}"
[ -r "$ledger" ] || exit 0

cwd=$(field cwd)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

sh "$ledger" repo-ledger "$cwd" >/dev/null 2>&1 && exit 0

sid=$(field session_id)
[ -n "$sid" ] || sid=${CLAUDE_CODE_SESSION_ID:-}
[ -n "$sid" ] || exit 0

resumed=''
path=$(sh "$ledger" path "$sid" 2>/dev/null) || exit 0
if [ -f "$path" ]; then
  open=$(sh "$ledger" open "$path" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\) open$/\1/p')
  [ -n "$open" ] && [ "$open" -gt 0 ] && resumed=" It already holds $open open item(s) from earlier in this session: sh ~/.claude/skills/wrap-up/ledger.sh open lists them."
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
  "Keep a ledger for /wrap-up. Each time this session makes something that outlives a command (a branch, worktree, stash entry, PR, server, background task, Monitor or cron, or a file outside the repo and your scratchpad), record it at once: sh ~/.claude/skills/wrap-up/ledger.sh taken '<kind> <item>', e.g. 'branch feat/x' or 'server :5173'. Nothing else can tell later which of these are this session's.$resumed"

exit 0
