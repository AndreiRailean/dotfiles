#!/bin/sh
# statusline-command.sh contract: print ONE line combining the user's real
# starship prompt with session stats read from the JSON payload Claude Code
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

# Fake starship: ignores the flags it is handed and replays a prompt shaped
# like the real thing — leading blank line from add_newline, the segments,
# then the bare `character` glyph the script is expected to drop.
cat > "$TMP/bin/starship" <<'STUB'
#!/bin/sh
printf '\n\033[34mfinance-notes\033[0m on \033[35mcustomer-names-cron\033[0m\n\033[32m❯\033[0m\n'
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
  "cwd": "/home/andrei/dotfiles",
  "model": {"id": "claude-opus-5[1m]", "display_name": "Opus 5 (1M context)"},
  "workspace": {"current_dir": "/home/andrei/dotfiles"},
  "effort": {"level": "high"},
  "fast_mode": false,
  "context_window": {"total_input_tokens": 123456, "context_window_size": 1000000, "used_percentage": 12, "remaining_percentage": 88},
  "rate_limits": {"five_hour": {"used_percentage": 50}, "seven_day": {"used_percentage": 19}}
}'

out=$(render_plain "$FULL")
assert_contains "$out" "finance-notes" "the starship prompt still renders"
assert_not_contains "$out" "❯" "the bare character glyph is still dropped"
assert_contains "$out" "ctx 123k" "context usage renders as a token count"
assert_not_contains "$out" "ctx 12%" "context usage is not shown as a percentage of the window"
assert_contains "$out" "5h 50%" "the five-hour rate limit renders"
assert_contains "$out" "7d 19%" "the seven-day rate limit renders"
assert_contains "$out" "Opus 5 1M" "the model name renders without the (… context) suffix"
assert_contains "$out" "high" "the effort level renders"
assert_not_contains "$out" "⚡" "no fast-mode bolt when fast mode is off"

lines=$(render "$FULL" | wc -l)
assert_eq "$lines" "0" "the whole line is emitted without a trailing newline"

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
assert_contains "$out" "finance-notes" "the prompt still renders on a minimal payload"

# A payload that isn't JSON at all must not take the line down.
out=$(printf 'not json' | bash "$SCRIPT" | sed -E "s/${ESC}\[[0-9;]*m//g")
assert_contains "$out" "finance-notes" "unparseable input still renders the prompt"
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
