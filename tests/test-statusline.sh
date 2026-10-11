#!/bin/sh
# statusline-command.sh contract: print TWO lines — the user's real starship
# prompt, then session stats read from the JSON payload Claude Code
# pipes in on stdin — tokens in the context window, plan rate limits, and the
# active model. Every stat segment is optional: Claude Code omits or nulls these keys
# early in a session, right after /compact, and on older versions, and the
# line must stay useful rather than print "ctx %" or crash.
#
# Driven through a fake `starship` on PATH and staged JSON on stdin, so the
# whole matrix runs with no starship install and no live session.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
SCRIPT="$REPO/claude/.claude/statusline-command.sh"

if [ -f "$SCRIPT" ]; then
  pass "the status line script exists"
else
  fail "the status line script exists"
  finish
fi

bash -n "$SCRIPT" && pass "statusline-command.sh parses" \
  || fail "statusline-command.sh parses"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/nohome"

# Fake starship: answers the two subcommands the script uses. print-config
# returns a format string behind the comment lines the real one prints (which
# name modules too, and must not be rendered). `module` draws each module the
# way starship does: optional plain prefix, a style, the text, a reset, a
# space. The directory is the --path basename; the branch comes from
# $STUB_BRANCH.
cat > "$TMP/bin/starship" <<'STUB'
#!/bin/bash
E=$'\033'
cmd=$1 mod=$2 path=""
while [ $# -gt 0 ]; do [ "$1" = --path ] && path=$2; shift; done
case "$cmd" in
  print-config)
    printf '# $all is shorthand for $time$battery\n'
    printf 'format = "$hostname$directory$git_branch$git_status$line_break$character"\n'
    ;;
  module)
    case "$mod" in
      hostname) printf '%s[1;34mbox%s[0m ' "$E" "$E" ;;
      directory) printf '%s[1;36m%s%s[0m ' "$E" "${path##*/}" "$E" ;;
      git_branch) printf 'on %s[1;35mB %s%s[0m ' "$E" "${STUB_BRANCH:-customer-names-cron}" "$E" ;;
      git_status) printf '%s[1;33m[!2]%s[0m ' "$E" "$E" ;;
      character) printf '%s[32m❯%s[0m ' "$E" "$E" ;;
      *) printf 'UNEXPECTED-%s ' "$mod" ;;
    esac
    ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/starship"

PATH="$TMP/bin:$PATH"
export PATH

ESC=$(printf '\033')
RED=$(printf '\033[31m')
YELLOW=$(printf '\033[33m')
GREEN=$(printf '\033[32m')

# Render the script against a payload, returning the raw (colored) line.
render() { printf '%s' "$1" | bash "$SCRIPT"; }

# Same, with every SGR escape stripped, for assertions about text content.
render_plain() { render "$1" | sed -E "s/${ESC}\[[0-9;]*m//g"; }

# A complete payload, matching the shape Claude Code documents: a 1M-context
# model holding 123,456 tokens (12%), both rate-limit windows present, fast
# mode off.
FULL='{
  "cwd": "/home/andrei/finance-notes",
  "model": {"id": "claude-opus-5[1m]", "display_name": "Opus 5 (1M context)"},
  "workspace": {"current_dir": "/home/andrei/dotfiles"},
  "effort": {"level": "high"},
  "fast_mode": false,
  "context_window": {"total_input_tokens": 123456, "context_window_size": 1000000, "used_percentage": 12, "remaining_percentage": 88},
  "rate_limits": {"five_hour": {"used_percentage": 50}, "seven_day": {"used_percentage": 19}}
}'

out=$(render_plain "$FULL")
assert_contains "$out" "finance-notes" "the starship prompt still renders"
assert_contains "$out" "on B customer-names-cron" "the git branch renders when it differs from the folder"
assert_contains "$out" "[!2]" "modules after the branch still render"
assert_not_contains "$out" "❯" "the bare character glyph is still dropped"
assert_not_contains "$out" "UNEXPECTED" "modules named only in print-config comments are not rendered"
assert_contains "$out" "ctx 123k" "context usage renders as a token count"
assert_not_contains "$out" "ctx 12%" "context usage is not shown as a percentage of the window"
assert_contains "$out" "5h 50%" "the five-hour rate limit renders"
assert_contains "$out" "7d 19%" "the seven-day rate limit renders"
assert_contains "$out" "Opus 5 1M" "the model name renders without the (… context) suffix"
assert_contains "$out" "high" "the effort level renders"
assert_not_contains "$out" "⚡" "no fast-mode bolt when fast mode is off"

lines=$(render "$FULL" | wc -l)
assert_eq "$lines" "1" "two lines are emitted, without a trailing newline"
assert_eq "$(render_plain "$FULL" | head -1 | grep -c ctx)" "0" "the stats are not on the prompt line"
assert_eq "$(render_plain "$FULL" | tail -1 | cut -c1-8)" "ctx 123k" "the stats line starts with the context count"

# Folder and branch trimming.
out=$(printf '%s' "$FULL" | STUB_BRANCH=finance-notes bash "$SCRIPT" | sed -E "s/${ESC}\[[0-9;]*m//g")
assert_not_contains "$out" "on B" "a branch named like its folder is left out"
assert_contains "$out" "[!2]" "leaving the branch out keeps the modules after it"

LONG=$(printf '%s' "$FULL" | sed 's#/home/andrei/finance-notes#/w/promote-beta-head-to-stable#')
out=$(printf '%s' "$LONG" | STUB_BRANCH=feat/very-long-branch-name bash "$SCRIPT" | sed -E "s/${ESC}\[[0-9;]*m//g")
assert_contains "$out" "box …beta-head-to-stable on" "a long folder keeps its last 20 characters"
assert_contains "$out" "on B feat/very-long-bran… [!2]" "a long branch keeps its first 20 characters"
assert_contains "$(printf '%s' "$LONG" | STUB_BRANCH=feat/very-long-branch-name bash "$SCRIPT")" "${ESC}[1;36m…beta-head-to-stable${ESC}[0m" "a cut folder keeps its color"

# Color thresholds. Rate limits: green under 50, yellow 50-79, red 80 and up.
# Context is judged in tokens, because a 1M window makes its percentage tiny:
# yellow from 200k (where idle compaction kicks in), red from 400k. The
# percentage thresholds still apply too, so a 200k-window model warns as well.
out=$(render "$FULL")
assert_contains "$out" "${GREEN}ctx 123k" "context under 200k tokens is green"
assert_contains "$out" "${YELLOW}5h 50%" "a rate limit window at 50% is yellow"

ctx() { printf '%s' "$FULL" | sed "s/\"total_input_tokens\": 123456/\"total_input_tokens\": $1/; s/\"used_percentage\": 12/\"used_percentage\": $2/"; }
assert_contains "$(render "$(ctx 199999 20)")" "${GREEN}ctx 200k" "199,999 tokens is still green (and rounds to 200k)"
assert_contains "$(render "$(ctx 266294 27)")" "${YELLOW}ctx 266k" "context at 200k tokens or more is yellow"
assert_contains "$(render "$(ctx 450000 45)")" "${RED}ctx 450k" "context at 400k tokens or more is red"
assert_contains "$(render "$(ctx 160000 80)")" "${RED}ctx 160k" "80% of a small window is red even under 400k tokens"
assert_contains "$(render "$(ctx 110000 55)")" "${YELLOW}ctx 110k" "50% of a small window is yellow even under 200k tokens"

# Formatting at the edges of the k scale.
assert_contains "$(render_plain "$(ctx 850 0)")" "ctx 850 " "under 1k tokens prints the raw count"
assert_contains "$(render_plain "$(ctx 1000000 100)")" "ctx 1.0M" "a full 1M window prints in millions"

# Older versions send used_percentage without total_input_tokens; keep the
# percentage rather than drop the segment.
NOTOK=$(printf '%s' "$FULL" | sed 's/"total_input_tokens": 123456, //')
assert_contains "$(render_plain "$NOTOK")" "ctx 12%" "without total_input_tokens the percentage is shown"

# Fractional percentages: the payload documents a number, not an integer, and
# a float would blow up the [ -ge ] threshold comparison.
FRAC=$(printf '%s' "$NOTOK" | sed 's/"used_percentage": 12/"used_percentage": 12.7/')
out=$(render_plain "$FRAC")
assert_contains "$out" "ctx 12%" "a fractional percentage is truncated, not passed to test -ge"

# Fast mode replaces nothing — it annotates the model segment.
FAST=$(printf '%s' "$FULL" | sed 's/"fast_mode": false/"fast_mode": true/')
assert_contains "$(render_plain "$FAST")" "⚡high" "fast mode marks the model segment"

# Absent and null stats. Claude Code nulls used_percentage before the first
# API call and again after /compact (total_input_tokens is then 0, which must
# not render as "ctx 0"); rate_limits is absent on API-key auth;
# older versions have no context_window at all.
NULLPCT=$(ctx 0 null)
out=$(render_plain "$NULLPCT")
assert_not_contains "$out" "ctx" "a null used_percentage prints no context segment"
assert_contains "$out" "5h 50%" "a null used_percentage still leaves the rate limits"

NOCTX='{"cwd": "/home/andrei", "model": {"display_name": "Sonnet 5"}}'
out=$(render_plain "$NOCTX")
assert_not_contains "$out" "ctx" "an absent context_window prints no context segment"
assert_not_contains "$out" "5h" "absent rate_limits print no rate limit segment"
assert_contains "$out" "Sonnet 5" "a display_name without a context suffix is left alone"
assert_contains "$out" "box" "the prompt still renders on a minimal payload"

# A payload that isn't JSON at all must not take the line down.
out=$(printf 'not json' | bash "$SCRIPT" | sed -E "s/${ESC}\[[0-9;]*m//g")
assert_contains "$out" "box" "unparseable input still renders the prompt"
assert_not_contains "$out" "ctx" "unparseable input prints no stats"

# The fallback path exists for when starship is missing — losing the context
# readout exactly then would be the wrong failure mode, so stats ride along.
# The sanitized PATH keeps jq (the script needs it to read the payload at all)
# while dropping the directory the real starship lives in, and HOME points at
# an empty dir so the ~/.local/bin/starship fallback misses too.
mkdir -p "$TMP/nojq"
ln -s "$(command -v jq)" "$TMP/nojq/jq"
out=$(printf '%s' "$FULL" | env PATH="$TMP/nojq:/usr/bin:/bin" HOME="$TMP/nohome" bash "$SCRIPT" \
  | sed -E "s/${ESC}\[[0-9;]*m//g")
assert_contains "$out" "ctx 123k" "the no-starship fallback still shows context usage"
assert_contains "$out" "Opus 5 1M" "the no-starship fallback still shows the model"

finish
