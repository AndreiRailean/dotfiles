#!/bin/sh
# behind-probe.sh — say, at session start, when the world moved.
#
# WHY THIS FILE EXISTS: a session that plans against a stale worktree does
# confident, wasted work. Measured on telik, 2026-09-20: a parallel session
# landed five PRs during one conversation, and the session that could not see
# them swept the issue tracker and filed three tickets for work that was
# already built and merged. Nothing was wrong with the reasoning; the inputs
# were a day old.
#
# It fetches, deliberately. A probe that compares against a stale remote ref
# reports "up to date" in exactly the situation it exists to catch, which is
# worse than not existing. The fetch is read-only and bounded; offline,
# unauthenticated or slow must cost a session nothing.
#
# Like its neighbours it performs NO judgment and writes NO files: it reports
# counts and leaves merging to the session. It must always exit 0 — a hook
# that fails is a hook that disrupts every session it runs in.
#
# Usage: behind-probe.sh   (hook payload JSON on stdin, unused)

set -u

# Drain stdin so the caller never blocks on a pipe nobody read.
cat >/dev/null 2>&1

emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1"
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0

timeout 8 git fetch origin --quiet --prune 2>/dev/null

# origin/HEAD is often absent on a clone made with --single-branch or by a
# tool, so it cannot be relied on. Fall back rather than exit: a repo with no
# origin/HEAD is the common case, not an error.
def=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
if [ -z "$def" ]; then
  for b in origin/main origin/master; do
    if git rev-parse --verify --quiet "$b" >/dev/null 2>&1; then def=$b; break; fi
  done
fi
[ -n "$def" ] || exit 0

count_behind() {
  n=$(git -C "$1" rev-list --count "HEAD..$def" 2>/dev/null) || n=0
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
here=$(count_behind "$top")

msg=''
[ "$here" -gt 0 ] && msg="This worktree is $here commit(s) behind $def."

# The main checkout is what the NEXT session starts from, and a merge done in
# another worktree or in the web UI leaves it behind with nothing to notice.
# ff-probe.sh catches the merges this session performs; this catches the rest.
main_wt=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print substr($0,10); exit}')
if [ -n "$main_wt" ] && [ "$main_wt" != "$top" ]; then
  there=$(count_behind "$main_wt")
  if [ "$there" -gt 0 ]; then
    msg="$msg The main checkout is $there commit(s) behind $def; fast-forward it per CLAUDE.md."
  fi
fi

[ -n "$msg" ] || exit 0
emit "$msg Someone else may have landed work — reconcile before planning or filing anything against this tree."
exit 0
