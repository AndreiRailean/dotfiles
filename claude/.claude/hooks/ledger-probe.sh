#!/bin/sh
# ledger-probe.sh — at session start, ask for the ledger the wrap-up reads;
# across a /clear, carry it.
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
# conversation that recorded them may no longer be in context.
#
# A /clear is the one event that loses the session's state: it starts a new
# session ID, so the ledger so far is under a name nothing reads, and the
# conversation step 5 of the wrap-up reads back over leaves context. It cannot
# be stopped from a hook, so both halves are handled: registered on SessionEnd
# too, this script runs `ledger.sh clear-out` when the reason is clear, and the
# SessionStart(clear) that follows runs `clear-in`, which carries the open
# items into the new ledger, then names the old ID and the transcript to read.
# That note goes out even where the repo keeps its own ledger, since a repo
# ledger keyed by session ID (telik's) is detached by a /clear in the same way.
# A SessionStart(clear) that finds no handoff says so: its ledger can read
# 0 open while the old one still holds items, and a wrap-up would call a
# /clear safe on that.
#
# Apart from that handoff it writes NO files: ledger.sh creates the ledger on
# the first line taken. It must always exit 0. A SessionStart hook that fails
# is noise at the top of every session.
#
# It needs jq, to read the payload and to write the note: a transcript path is
# copied from one into the other, and only a real JSON parser and encoder carry
# any character in it across. jq comes with Claude on every machine these
# skills run on (the machine's definition installs it, since the dotfiles are
# config, not apps: docs/adr/20261027-dotfiles-are-config-not-apps.md). Where
# it is missing the probe says nothing, as config must when its app is absent,
# and doctor.sh reports it.
#
# Usage: ledger-probe.sh   (SessionStart or SessionEnd hook payload on stdin)

set -u

payload=''
line=''
while IFS= read -r line || [ -n "$line" ]; do
  payload="$payload$line"
  line=''
done

ledger="${LEDGER_SH:-$HOME/.claude/skills/wrap-up/ledger.sh}"
[ -r "$ledger" ] || exit 0

# Every field in one pass, each quoted for the shell by @sh. Only the first
# JSON value counts, and a field that is not a string or number reads as empty:
# @sh writes an array as several words, which the eval would run.
fields=$(printf '%s' "$payload" | jq -rn '
  def s: if type == "string" or type == "number" then tostring else "" end;
  (first(inputs) // {}) as $p | if ($p | type) == "object" then $p else {} end
  | @sh "sid=\(.session_id | s) event=\(.hook_event_name | s) reason=\(.reason | s) transcript=\(.transcript_path | s) cwd=\(.cwd | s) source=\(.source | s)"' 2>/dev/null) || exit 0
eval "$fields"

note() {
  jq -cn --arg c "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
}

[ -n "$sid" ] || sid=${CLAUDE_CODE_SESSION_ID:-}
[ -n "$sid" ] || exit 0

if [ "$event" = SessionEnd ]; then
  [ "$reason" = clear ] && sh "$ledger" clear-out "$sid" "$transcript" >/dev/null 2>&1
  exit 0
fi

[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$PWD"

cleared=''
if [ "$source" = clear ]; then
  if handed=$(sh "$ledger" clear-in "$sid" 2>/dev/null); then
    { read -r old; read -r transcript; read -r carried; } <<EOF
$handed
EOF
    cleared="This session began with /clear, which gave it a new session ID; it was $old, and anything recorded under that ID is this session's too."
    [ "${carried:-0}" -gt 0 ] 2>/dev/null && cleared="$cleared $carried open item(s) were carried from that ledger into this one."
    [ -n "$transcript" ] && cleared="$cleared The conversation before the /clear is at $transcript; a /wrap-up reads it for what existed only there."
  else
    dir=$(sh "$ledger" path "$sid" 2>/dev/null) && dir=${dir%/*}
    cleared="This session began with /clear, which gave it a new session ID, but no handoff from the session before it arrived, so nothing that session recorded was carried here. Until its ledger is found (likely the newest file in ${dir:-the ledger directory}, by modification time), a /wrap-up cannot call a /clear safe."
  fi
fi

if sh "$ledger" repo-ledger "$cwd" >/dev/null 2>&1; then
  [ -n "$cleared" ] || exit 0
  note "$cleared"
  exit 0
fi

resumed=''
path=$(sh "$ledger" path "$sid" 2>/dev/null) || exit 0
if [ -f "$path" ]; then
  open=$(sh "$ledger" open "$path" 2>/dev/null | sed -n 's/^\([0-9][0-9]*\) open$/\1/p')
  [ -n "$open" ] && [ "$open" -gt 0 ] && resumed=" It already holds $open open item(s) from earlier in this session: sh ~/.claude/skills/wrap-up/ledger.sh open lists them."
fi

note "Keep a ledger for /wrap-up. Each time this session makes something that outlives a command (a branch, worktree, stash entry, PR, server, background task, Monitor or cron, or a file outside the repo and your scratchpad), record it at once: sh ~/.claude/skills/wrap-up/ledger.sh taken '<kind> <item>', e.g. 'branch feat/x' or 'server :5173'. Nothing else can tell later which of these are this session's.$resumed${cleared:+ $cleared}"

exit 0
