#!/bin/sh
# review-probe.sh — after a PR is opened, ask for a fresh review before it is
# merged.
#
# WHY THIS FILE EXISTS: a review before merge is a reflex, not a task, and a
# reflex that lives in prose does not fire. Measured 2026-10-18..24 in one
# repo that wrote the rule down: one session merged twelve PRs and ran a fresh
# review before one of them. The only prompt to review came at the end of the
# session, after every merge, and the reviews it prompted then found twelve
# defects. A plugin had been supplying a "review before merging" reminder,
# and turning it off removed the only nudge. Same reasoning as adr-probe.sh
# and ff-probe.sh: hang the question off an event that fires on its own, here
# the gap between opening a PR and merging it.
#
# A repo that writes its own review rule can ship its own
# .claude/hooks/review-probe.sh, and then this one is silent there, so the
# question is asked once and in that repo's words.
#
# It performs NO judgement and writes NO files. It runs on EVERY Bash tool
# call, so the match uses shell `case` only, and it must always exit 0.
#
# Usage: review-probe.sh   (PostToolUse hook payload JSON on stdin)

set -u

payload=''
line=''
while IFS= read -r line || [ -n "$line" ]; do
  payload="$payload$line"
  line=''
done

[ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/hooks/review-probe.sh" ] && exit 0

# Match only the command half, and only where gh pr create is invoked rather
# than quoted in prose, for the reasons ff-probe.sh records.
head="${payload%%\"tool_response\"*}"
case "$head" in
  *'"command":"gh pr create'*|*'"command": "gh pr create'*) ;;
  *'&& gh pr create'*|*'&&gh pr create'*) ;;
  *'; gh pr create'*|*';gh pr create'*) ;;
  *'\ngh pr create'*) ;;
  *) exit 0 ;;
esac
# A create that failed opened nothing to review.
case "$payload" in
  *'already exists'*|*'could not create'*|*'GraphQL:'*) exit 0 ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "A PR was opened. Before merging it, have a fresh agent with no stake in it review the final diff, briefed to find what fails silently rather than to comment on style, and fix what it finds. If the repo documents its own review rule, follow that. Skipping the review is a choice to say out loud, not a default."
exit 0
