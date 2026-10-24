#!/bin/sh
# ledger.sh — the session ledger the wrap-up skill works from.
#
#   ledger.sh taken|returned|reviewed TEXT   append one line to this session's ledger
#   ledger.sh open [FILE]                    list what is still open, then a count
#   ledger.sh path [SESSION_ID]              print a session's ledger path
#   ledger.sh procs [DIR]                    list processes running inside the worktree
#   ledger.sh project-skill [DIR]            print the repo's own wrap-up skill, if any
#   ledger.sh repo-ledger [DIR]              succeed if the repo asks for its own ledger
#
# WHY THIS FILE EXISTS: a wrap-up must return only what this session took, and
# none of that can be recovered afterwards — a branch does not carry its
# author, a server does not say who started it. The first wrap-up skill said
# "delete only branches this session created", and the first session to follow
# it globbed feat/* and swept up another session's two. So the session writes a
# line when each thing comes into existence, and the wrap-up reads it back.
#
# The ledger lives under XDG state, keyed by session ID, because the
# alternatives each lost one: the scratchpad is under /tmp and a reboot empties
# it while the session survives (telik lost two days of ledger that way), and a
# file in the worktree needs a gitignore entry no generic tool can count on.
# The session ID survives a resume, so a resumed session finds its own again.
#
# The format and the counting are telik's (cli/ledger-open.sh there), kept in a
# script for the reason telik found: the skill loader replaces $0..$9 in a
# skill body with the invocation's arguments, so awk written inline in
# SKILL.md reads the user's words as its fields.
#
# Line format: `taken: <kind> <item> (<note>)`. A taken: and a returned: line
# match on the text before a TRAILING parenthesised note, and only on that, so
# a date or PR number in the note does not stop a match. Items are counted, +1
# per taken and -1 per returned, so one taken again after it was returned is
# open again; a return with nothing open is reported, never counted below zero. The file is append-only: nothing here rewrites or deletes it.
#
# project-skill exists because a personal skill shadows a project skill of the
# same name, so ~/.claude/skills/wrap-up runs even in a repo that wrote its own.
# The skill hands over to the repo's file when this prints one. repo-ledger
# decides where the session-start probe stays quiet, which is narrower: only
# where the repo's always-loaded instructions ask for a ledger of their own.
set -u

state="${XDG_STATE_HOME:-$HOME/.local/state}/claude/ledger"

ledger_path() {
	sid=${1:-${CLAUDE_CODE_SESSION_ID:-}}
	if [ -z "$sid" ]; then
		echo "no CLAUDE_CODE_SESSION_ID, so no ledger of this session's; name one" >&2
		return 1
	fi
	printf '%s/%s\n' "$state" "$sid"
}

cmd=${1:-}
[ $# -gt 0 ] && shift

case "$cmd" in
taken | returned | reviewed)
	text=$(printf '%s' "$*" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
	[ -n "$text" ] || { echo "usage: ledger.sh $cmd TEXT" >&2; exit 2; }
	f=$(ledger_path) || exit 1
	mkdir -p "${f%/*}" || exit 1
	printf '%s: %s\n' "$cmd" "$text" >>"$f" || exit 1
	echo "$f: $cmd: $text"
	;;
open)
	if [ -n "${1:-}" ]; then f=$1; else f=$(ledger_path) || exit 1; fi
	[ -f "$f" ] || { echo "no ledger at $f" >&2; exit 1; }
	# An open item is printed as its last taken: line wrote it, note and all,
	# since the key cuts a trailing "(...)" and a real name can end in one
	# ("report (1)"); the skill removes files by exact path. A returned: with
	# nothing open under its key is reported and not counted, so a doubled
	# return cannot push the count below zero and hide the next taken:.
	awk '
	function item(s) { sub(/ \([^()]*\)$/, "", s); return s }
	{ sub(/\r$/, ""); sub(/[ \t]+$/, ""); gsub(/  +/, " ") }
	/^taken: / {
		t = substr($0, 8); k = item(t)
		if (!(k in n)) { order[++m] = k; n[k] = 0 }
		n[k]++; shown[k] = t; next
	}
	/^returned: / {
		k = item(substr($0, 11))
		if (!(k in n) || n[k] <= 0) {
			printf "ledger line %d returns something with nothing open under that name, so it is not counted: %s\n", NR, $0 > "/dev/stderr"
			next
		}
		n[k]--; next
	}
	/^reviewed: / { last = substr($0, 11); next }
	/^#/ || /^$/  { next }
	{ printf "ledger line %d is not taken:, returned: or reviewed:, so it is not counted: %s\n", NR, $0 > "/dev/stderr" }
	END {
		open = 0
		for (i = 1; i <= m; i++) if (n[order[i]] > 0) { print "open: " shown[order[i]]; open++ }
		print open " open"
		if (last != "") print "last reviewed: " last
	}' "$f"
	;;
path)
	ledger_path "${1:-}"
	;;
procs)
	# What outlived the command that started it, in any repo: a process whose
	# working directory is inside the worktree. The repo wrap-ups grep ps for
	# names they know (astro, chromium); a generic one cannot know them, but a
	# server or test runner started here runs here.
	#
	# These are CANDIDATES, not this session's: another session working in the
	# same checkout, a terminal pane opened here, an MCP server Claude started
	# here all show too, and the skill says so. Left out are only what is
	# certainly not a leftover: this script's chain of parents (the Bash tool's
	# shell, the claude process), its own subshells, and anything in a worktree
	# nested under this one (.claude/worktrees/, .worktrees/), which is that
	# worktree's. The parent chain comes from ps, not /proc, so it holds on
	# macOS as well.
	top=$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || top=$(cd "${1:-.}" && pwd -P) || exit 1
	ppid() { ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '; }
	skip=" $$ "
	p=$$
	while p=$(ppid "$p") && [ -n "$p" ] && [ "$p" -gt 1 ]; do
		skip="$skip$p "
	done
	nested=$(git -C "$top" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' |
		while IFS= read -r w; do
			case "$w/" in "$top"/) ;; "$top"/*) printf '%s\n' "$w" ;; esac
		done)
	if [ -d /proc/self ]; then
		for d in /proc/[0-9]*; do
			c=$(readlink "$d/cwd" 2>/dev/null) || continue
			printf '%s %s\n' "${d#/proc/}" "$c"
		done
	else
		lsof -a -d cwd -Fpn 2>/dev/null | awk '/^p/ { p = substr($0, 2) } /^n/ { print p, substr($0, 2) }'
	fi | while read -r pid c; do
		case "$c/" in "$top"/*) ;; *) continue ;; esac
		case "$skip" in *" $pid "*) continue ;; esac
		[ "$(ppid "$pid")" = "$$" ] && continue
		inner=0
		if [ -n "$nested" ]; then
			while IFS= read -r w; do
				case "$c/" in "$w"/*) inner=1 ;; esac
			done <<EOF
$nested
EOF
		fi
		[ "$inner" -eq 0 ] || continue
		ps -o pid=,etime=,args= -p "$pid" 2>/dev/null
	done
	;;
repo-ledger)
	# Whether the repo keeps its own ledger: it has its own wrap-up AND an
	# always-loaded instruction file says so. The wrap-up alone is not enough:
	# andrei.md's asks for a ledger only in its skill body, which is read at the
	# end, and framestep's keeps none, so in both the session-start request is
	# the only one a session gets. telik's CLAUDE.md asks for its own, and two
	# requests for two ledgers would compete there.
	sh "$0" project-skill "${1:-.}" >/dev/null || exit 1
	d=$(cd "${1:-.}" 2>/dev/null && pwd -P) || exit 1
	root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || root=$d
	while :; do
		for f in "$d/CLAUDE.md" "$d/.claude/CLAUDE.md" "$d/CLAUDE.local.md" "$d/AGENTS.md"; do
			[ -f "$f" ] && grep -qi 'ledger' "$f" && exit 0
		done
		{ [ "$d" = "$root" ] || [ "$d" = / ]; } && break
		d=$(dirname "$d")
	done
	exit 1
	;;
project-skill)
	self="$(cd "$(dirname "$0")" && pwd -P)/SKILL.md"
	d=$(cd "${1:-.}" 2>/dev/null && pwd -P) || exit 1
	root=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || root=''
	# From the directory up to the repo root, as Claude Code finds nested
	# skills. Outside a repo only the directory itself: walking up from a
	# non-repo directory under $HOME would find ~/.claude/skills/wrap-up, which
	# is this skill, and -ef is what rules that out wherever it is reached from.
	while :; do
		f="$d/.claude/skills/wrap-up/SKILL.md"
		if [ -f "$f" ] && ! [ "$f" -ef "$self" ]; then
			echo "$f"
			exit 0
		fi
		{ [ -z "$root" ] || [ "$d" = "$root" ] || [ "$d" = / ]; } && break
		d=$(dirname "$d")
	done
	exit 1
	;;
*)
	sed -n '2,9s/^# \{0,1\}//p' "$0" >&2
	exit 2
	;;
esac
