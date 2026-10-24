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
# It fires on the outcome, not the spelling. The command names `gh` and
# `pr create` in any form ($(...), an env prefix, -R, bash -c), and either
# the response carries a PR URL (/pull/), which prose and a failed create
# never print, or the command captures the output in $(...), which hides the
# URL. A first version matched the spelling, as ff-probe.sh does, and a review
# found it missed `n=$(gh pr create ...)`, fired on prose that began a line
# with the command, and let a PR body mentioning "already exists" silence a
# create that succeeded.
#
# Known limit: prose inside a command that quotes the captured form, such as
# a commit message describing `n=$(gh pr create ...)`, fires it, since the
# captured form prints no URL to tell the two apart. That happened while this
# file was being written; it costs one ignored sentence, and telling quoted
# text from invoked text needs a shell parser.
#
# A repo that writes its own review rule can ship and register its own
# .claude/hooks/review-probe.sh, and this one is then silent there, so the
# question is asked once and in that repo's words. Not when the command
# changes directory: the PR may be in another repo, where that rule is the
# wrong one, and the repo's probe stands aside for this one then.
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

cmd="${payload%%\"tool_response\"*}"
resp="${payload#*\"tool_response\"}"
[ "$resp" = "$payload" ] && resp=''

case "$cmd" in
  *'gh '*'pr create'*) ;;
  *) exit 0 ;;
esac
case "$resp" in
  *'/pull/'*) ;;
  *)
    case "$cmd" in
      *'$(gh '*'pr create'*|*'$( gh '*'pr create'*) ;;
      *) exit 0 ;;
    esac
    ;;
esac

# Defer to the repo's own probe only where it is registered and will speak.
case "$cmd" in
  *'cd '*) ;;
  *)
    own="${CLAUDE_PROJECT_DIR:-}/.claude"
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$own/hooks/review-probe.sh" ] \
      && grep -qs 'review-probe.sh' "$own/settings.json" "$own/settings.local.json"; then
      exit 0
    fi
    ;;
esac

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "A PR was opened. Before merging it, have a fresh agent with no stake in it review the final diff, briefed to find what fails silently rather than to comment on style, and fix what it finds. If the repo documents its own review rule, follow that. Skipping the review is a choice to say out loud, not a default."
exit 0
