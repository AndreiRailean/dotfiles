#!/bin/sh
# adr-probe.sh — ask whether something ADR-worthy just happened.
#
# WHY THIS FILE EXISTS: knowledge only gets captured if the question gets
# asked. A skill that must be invoked by hand never fires — /handoff produces
# good output and still goes unused, because remembering to run it is the part
# that fails. So the question is hung off events that fire on their own.
#
# This script deliberately performs NO judgment and writes NO files. It emits a
# short probe and exits. That keeps it fast, independently testable, and unable
# to corrupt a repo. Deciding whether a record is warranted, and writing it, is
# the record-decision skill's job.
#
# It runs on EVERY Bash tool call, so the commit path uses shell `case` only —
# no subprocesses. It must always exit 0: a hook that fails is a hook that
# disrupts every command the agent runs.
#
# Usage: adr-probe.sh commit|subagent   (hook payload JSON on stdin)

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
  commit)
    # Matchers match the tool NAME, not the command text, so this fires on
    # every Bash call and has to filter here.
    case "$payload" in
      *'git commit'*) ;;
      *) exit 0 ;;
    esac
    # A commit that changed nothing is not a decision.
    case "$payload" in
      *'nothing to commit'*) exit 0 ;;
    esac
    emit PostToolUse "A git commit was attempted. If it succeeded, does it encode a decision, or record an approach tried and abandoned? If yes, invoke record-decision. If no, continue silently."
    ;;
  subagent)
    # Explore and Plan are defined as all tools EXCEPT Write. Telling them to
    # write a file sends them into a wall, so they report back as text and the
    # parent records it.
    agent_type=$(printf '%s' "$payload" | sed -n 's/.*"agent_type":"\([^"]*\)".*/\1/p')
    case "$agent_type" in
      Explore|Plan)
        emit SubagentStop "Before returning: if you found a decision or a dead end worth recording, state it plainly in your final message. You do not have Write access, so the parent will record it."
        ;;
      *)
        emit SubagentStop "Before returning: does your work encode a decision, or record an approach tried and abandoned? If yes, invoke record-decision. If no, return silently."
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

exit 0
