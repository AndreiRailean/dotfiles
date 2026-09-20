#!/bin/sh
# ff-probe.sh â ask whether the main checkout needs fast-forwarding.
#
# WHY THIS FILE EXISTS: a post-merge fast-forward is a reflex, not a task, and
# a reflex that lives in prose does not fire. The rule existed for months as one
# clause inside andrei.md's steward skill, which only reaches an agent that
# invoked that skill, in that repo. Every other session merged a PR and left
# main behind, so the next session started from stale code. Same reasoning as
# adr-probe.sh: hang the question off an event that fires on its own.
#
# This script performs NO judgment, runs NO git, and writes NO files. It emits a
# short probe and exits. The agent decides and acts, so a wrong guess here costs
# one sentence rather than a surprising checkout.
#
# It cannot see a merge it was not present for â one done in the web UI, or one
# the user simply reports in chat. That half is covered in CLAUDE.md, which is
# read unconditionally.
#
# It runs on EVERY Bash tool call, so the merge path uses shell `case` only â
# no subprocesses. It must always exit 0: a hook that fails is a hook that
# disrupts every command the agent runs.
#
# Usage: ff-probe.sh merge   (hook payload JSON on stdin)

set -u

mode="${1:-}"
payload=''
line=''
while IFS= read -r line || [ -n "$line" ]; do
  payload="$payload$line"
  line=''
done

# $1 = hookEventName, $2 = probe text
emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$1" "$2"
}

case "$mode" in
  merge)
    # Match only the command half of the payload, for the reason adr-probe.sh
    # records: tool_response carries command OUTPUT, so any grep of a file
    # mentioning the phrase would otherwise fire the probe.
    head="${payload%%\"tool_response\"*}"

    # And require the phrase to be INVOKED, not quoted. Matching it anywhere in
    # the command fired this probe three times in its first hour — on a heredoc
    # writing CLAUDE.md, on a commit message explaining the hook, and on an
    # issue body describing the rule. Prose puts a space before it; a shell puts
    # the start of the command or a separator there.
    #
    # Deliberately NOT solved by demanding gh own confirmation instead: gh pr
    # merge prints nothing when stdout is not a terminal, which is the normal
    # case here, and requiring the output missed a real merge.
    case "$head" in
      *'"command":"gh pr merge'*|*'"command": "gh pr merge'*) ;;
      *'&& gh pr merge'*|*'&&gh pr merge'*) ;;
      *'; gh pr merge'*|*';gh pr merge'*) ;;
      *'\ngh pr merge'*) ;;
      *) exit 0 ;;
    esac

    # A merge that did not happen leaves nothing to fast-forward to. The last
    # of these is --auto, which only queues one.
    case "$payload" in
      *'not mergeable'*|*'not in a mergeable state'*|*'Draft pull request'*|*'will be automatically merged'*) exit 0 ;;
    esac

    emit PostToolUse "A PR merge was attempted. If it succeeded, fast-forward the main checkout so the next session starts from it: git -C <main checkout> fetch origin --prune, then git -C <main checkout> merge --ff-only origin/main. Use git -C rather than cd, since you are probably in a worktree. If it refuses, or the checkout is dirty, report that rather than forcing it."
    ;;
  *)
    exit 0
    ;;
esac

exit 0
