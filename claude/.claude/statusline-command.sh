#!/bin/bash
# Status line: render the user's ACTUAL starship prompt (~/.config/starship.toml)
# by invoking the real `starship` binary, rather than hand-porting the config
# into a separate implementation that could drift from it. This guarantees
# the status line always matches what the terminal shows, including future
# starship.toml edits.
#
# Then append the session stats Claude Code stops showing here: context window
# usage, the two plan rate-limit windows, and the active model. Configuring a
# custom status line suppresses the footer hint row, and the `N% context used`
# readout lives in that row — so once this script exists, it owes the user that
# number back.
#
# Falls back to a plain colored `user@host:cwd` (derived from the ~/.bashrc
# PS1 fallback) if starship can't be found or produces no output, so the
# status line degrades instead of going blank.

input=$(cat)

# One jq pass for every field the line needs. The status line repaints on
# every turn, so a jq process per field would be a pile of processes per
# repaint. Missing and null fields both come back as empty strings, which is
# what the render below treats as "skip this segment".
#
# One field per line, read one at a time: splitting a single tab-separated
# line would silently drop empty fields, because tab is IFS whitespace and
# `read` collapses runs of it. Empty fields are the normal case here, so that
# would shift every later value into the wrong variable.
{
  IFS= read -r cwd
  IFS= read -r ctx_pct
  IFS= read -r rl_5h
  IFS= read -r rl_7d
  IFS= read -r model
  IFS= read -r fast
  IFS= read -r effort
} <<< "$(
  printf '%s' "$input" | jq -r '[
    (.cwd // ""),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.model.display_name // ""),
    (if .fast_mode then "1" else "" end),
    (.effort.level // "")
  ] | .[]' 2>/dev/null)"
[ -z "$cwd" ] && cwd=$(pwd)

RESET=$'\033[0m'
DIM=$'\033[2m'
RED=$'\033[31m'
YELLOW=$'\033[33m'
GREEN=$'\033[32m'

# Percentages arrive as JSON numbers and may be fractional, so drop any
# decimal part and reject anything non-numeric rather than feed it to the
# integer comparisons in pct_color.
pct_int() {
  local n=${1%%.*}
  case "$n" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s' "$n"
}

# One scale for every percentage on the line, context window and plan windows
# alike, so a red segment always means the same thing.
pct_color() {
  if [ "$1" -ge 80 ]; then
    printf '%s' "$RED"
  elif [ "$1" -ge 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# Build the stats half of the line. Every segment is independently optional:
# used_percentage is null before the first API call and again after /compact,
# rate_limits is absent when authenticating with an API key, and versions
# before 2.1.x send none of it.
render_stats() {
  local segs=() n name suffix joined s

  if n=$(pct_int "$ctx_pct"); then
    segs+=("$(pct_color "$n")ctx ${n}%${RESET}")
  fi
  if n=$(pct_int "$rl_5h"); then
    segs+=("$(pct_color "$n")5h ${n}%${RESET}")
  fi
  if n=$(pct_int "$rl_7d"); then
    segs+=("$(pct_color "$n")7d ${n}%${RESET}")
  fi

  if [ -n "$model" ]; then
    # "Opus 5 (1M context)" -> "Opus 5 1M". The window size is worth keeping;
    # the word "context" next to a context percentage is not. Names without
    # that suffix pass through untouched.
    name=${model/(/}
    name=${name/ context)/}
    suffix=""
    [ -n "$fast" ] && suffix="⚡"
    [ -n "$effort" ] && suffix="$suffix$effort"
    [ -n "$suffix" ] && name="$name $suffix"
    segs+=("${DIM}${name}${RESET}")
  fi

  for s in "${segs[@]}"; do
    if [ -n "$joined" ]; then
      joined="$joined ${DIM}·${RESET} $s"
    else
      joined="$s"
    fi
  done
  printf '%s' "$joined"
}

stats=$(render_stats)

# Append the stats to whatever prompt was printed just before this call.
print_stats() {
  [ -n "$stats" ] && printf ' %s·%s %s' "$DIM" "$RESET" "$stats"
  return 0
}

render_fallback() {
  user=$(whoami)
  host=$(hostname -s)
  dir="${cwd/#$HOME/\~}"

  chroot=""
  if [ -n "${debian_chroot:-}" ]; then
    chroot="$debian_chroot"
  elif [ -r /etc/debian_chroot ]; then
    chroot=$(cat /etc/debian_chroot)
  fi

  [ -n "$chroot" ] && printf "(%s)" "$chroot"
  printf "\033[2;32m%s@%s\033[0m:\033[2;34m%s\033[0m" "$user" "$host" "$dir"
}

# Resolve the starship binary. A status-line invocation may run with a
# minimal PATH that doesn't include ~/.local/bin, so fall back to the known
# install location before giving up.
STARSHIP=$(command -v starship 2>/dev/null)
if [ -z "$STARSHIP" ] && [ -x "$HOME/.local/bin/starship" ]; then
  STARSHIP="$HOME/.local/bin/starship"
fi

if [ -z "$STARSHIP" ]; then
  render_fallback
  print_stats
  exit 0
fi

# Approximation: the JSON payload has no terminal width field, so fall back
# to $COLUMNS (often unset for non-interactive invocations) or 80.
width="${COLUMNS:-80}"

# Charge the stats against starship's width budget, so a long prompt truncates
# itself instead of pushing the stats off the right edge. Measured with the
# colors stripped, since escape codes take no columns.
if [ -n "$stats" ]; then
  stats_plain=$(printf '%s' "$stats" | sed -E 's/\x1b\[[0-9;]*m//g')
  width=$((width - ${#stats_plain} - 3))
  [ "$width" -lt 20 ] && width=20
fi

# --path/--logical-path (both) + PWD (both) are required: the `directory`
# module renders off the logical PWD, and `--path` alone renders whatever
# directory this script happens to execute in, not Claude Code's cwd.
# STARSHIP_SHELL must be unset, or starship wraps every color code in bash
# readline markers (\[ \]) that a status line would print literally.
raw=$(env -u STARSHIP_SHELL PWD="$cwd" "$STARSHIP" prompt \
  --path "$cwd" --logical-path "$cwd" --status 0 --jobs 0 -w "$width" 2>/dev/null)

if [ -z "$raw" ]; then
  render_fallback
  print_stats
  exit 0
fi

# Output is multi-line: a leading blank line (add_newline=true), the
# rendered segments, then the bare `character` glyph on its own line. Strip
# ANSI/OSC escapes on a scratch copy of each line just to test whether it's
# blank or glyph-only; keep the ORIGINAL (colored) line when it passes, so
# colors survive into the joined single-line result.
result=""
while IFS= read -r line; do
  stripped=$(printf '%s' "$line" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*(\x07|\x1b\\)//g')
  test_str="${stripped#"${stripped%%[![:space:]]*}"}"
  test_str="${test_str%"${test_str##*[![:space:]]}"}"
  [ -z "$test_str" ] && continue
  case "$test_str" in
    '❯'|'❮'|'$'|'>'|'»'|'➜') continue ;;
  esac
  orig="${line%"${line##*[![:space:]]}"}"
  if [ -n "$result" ]; then
    result="$result $orig"
  else
    result="$orig"
  fi
done <<< "$raw"

if [ -z "$result" ]; then
  render_fallback
  print_stats
  exit 0
fi

printf '%s' "$result"
print_stats
