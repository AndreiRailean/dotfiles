#!/bin/bash
# Status line, two lines. The first is the user's ACTUAL starship prompt
# (~/.config/starship.toml), drawn module by module by the real `starship`
# binary rather than hand-ported into a separate implementation that could
# drift from it, so future starship.toml edits show up here too. Two things
# differ from the terminal: long folder and branch names are cut short, and
# the branch is left out when it just repeats the folder name.
#
# The second line is the session stats Claude Code stops showing here: tokens
# in the context window, the two plan rate-limit windows, and the active
# model. Configuring a custom status line suppresses the footer hint row, and
# the `N% context used` readout lives in that row — so once this script
# exists, it owes the user that number back.
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
  IFS= read -r ctx_tokens
  IFS= read -r rl_5h
  IFS= read -r rl_7d
  IFS= read -r model
  IFS= read -r fast
  IFS= read -r effort
} <<< "$(
  printf '%s' "$input" | jq -r '[
    (.cwd // ""),
    (.context_window.used_percentage // ""),
    (.context_window.total_input_tokens // ""),
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

# Context is shown in tokens, not as a percentage of the window: on a 1M-token
# model the percentage sits in single digits for a whole session. Yellow from
# 200k, where idle compaction starts to apply, red from 400k. The percentage
# thresholds still count, so a 200k-window model warns before it is full.
CTX_WARN_TOKENS=200000
CTX_HOT_TOKENS=400000

ctx_color() {
  if [ "$1" -ge "$CTX_HOT_TOKENS" ] || [ "$2" -ge 80 ]; then
    printf '%s' "$RED"
  elif [ "$1" -ge "$CTX_WARN_TOKENS" ] || [ "$2" -ge 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# 850 -> 850, 83522 -> 84k, 1000000 -> 1.0M. Same width as the "10%" it replaced.
fmt_tokens() {
  if [ "$1" -lt 1000 ]; then
    printf '%s' "$1"
  elif [ "$1" -lt 999500 ]; then
    printf '%sk' "$((($1 + 500) / 1000))"
  else
    local tenths=$((($1 + 50000) / 100000))
    printf '%s.%sM' "$((tenths / 10))" "$((tenths % 10))"
  fi
}

# Build the stats half of the line. Every segment is independently optional:
# used_percentage is null before the first API call and again after /compact,
# rate_limits is absent when authenticating with an API key, and versions
# before 2.1.x send none of it.
render_stats() {
  local segs=() n t name suffix joined s

  # used_percentage gates the segment: it is null whenever there is no usage
  # to report, while total_input_tokens is 0 then rather than null. Versions
  # that send no token count keep the percentage.
  if n=$(pct_int "$ctx_pct"); then
    if t=$(pct_int "$ctx_tokens") && [ "$t" -gt 0 ]; then
      segs+=("$(ctx_color "$t" "$n")ctx $(fmt_tokens "$t")${RESET}")
    else
      segs+=("$(pct_color "$n")ctx ${n}%${RESET}")
    fi
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

# The stats get a line of their own, so a long prompt line can never push
# them out of view.
print_stats() {
  [ -n "$stats" ] && printf '\n%s' "$stats"
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

# Longest folder or branch name shown before it is cut with an ellipsis.
# Worktree folders and branches carry whole task descriptions in their names,
# and left uncut they crowd everything else off the line.
NAME_MAX=20

# Cut the styled name inside one module's output to NAME_MAX characters,
# keeping its colors and any symbol in front of it. A module renders as: plain prefix ("on "), one SGR
# escape, the name, a reset, then anything after it (git_status, the
# read-only lock). Only the name is cut: from the left for a path, so the
# folder you are in survives, and from the right for a branch, whose prefix
# says what kind of work it is.
cut_name() {
  local out=$1 side=$2 pre sgr rest body post lead LC_ALL=C.UTF-8
  case "$out" in *$'\033['*m*) ;; *) printf '%s' "$out"; return ;; esac
  pre=${out%%$'\033['*}
  rest=${out#"$pre"}
  sgr=${rest%%m*}m
  rest=${rest#"$sgr"}
  body=${rest%%$'\033['*}
  post=${rest#"$body"}
  # A module symbol (the branch glyph) sits inside the style with a space
  # after it; it is not part of the name.
  lead=${body%"${body##* }"}
  body=${body#"$lead"}
  if [ "${#body}" -gt "$NAME_MAX" ]; then
    if [ "$side" = left ]; then
      body="…${body:$((${#body} - NAME_MAX + 1))}"
    else
      body="${body:0:$((NAME_MAX - 1))}…"
    fi
  fi
  printf '%s%s%s%s%s' "$pre" "$sgr" "$lead" "$body" "$post"
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

# Render the prompt one module at a time, in the order starship.toml's
# `format` lists them, so the folder and branch can be trimmed on their own.
# Each module is still drawn by starship from the real config.
# --path/--logical-path (both) + PWD (both) are required: the `directory`
# module renders off the logical PWD, and `--path` alone renders whatever
# directory this script happens to execute in, not Claude Code's cwd.
# STARSHIP_SHELL must be unset, or starship wraps every color code in bash
# readline markers (\[ \]) that a status line would print literally.
starship_module() {
  env -u STARSHIP_SHELL PWD="$cwd" "$STARSHIP" module "$1" \
    --path "$cwd" --logical-path "$cwd" 2>/dev/null
}

# `format` comes back as one TOML string; pull the $module and ${custom.x}
# references out of it. The comment lines print-config adds name modules too
# (the $all expansion), so they are dropped first.
modules=$(env -u STARSHIP_SHELL "$STARSHIP" print-config format 2>/dev/null \
  | grep -v '^[[:space:]]*#' \
  | grep -oE '\$\{[a-z0-9_.-]+\}|\$[a-z0-9_]+' | tr -d '${}')

folder=${cwd%/}
folder=${folder##*/}
result=""
for m in $modules; do
  case "$m" in
    line_break | character) continue ;;
  esac
  out=$(starship_module "$m")
  case "$m" in
    directory) out=$(cut_name "$out" left) ;;
    git_branch)
      # In a worktree the branch usually repeats the folder name; say it once.
      plain=$(printf '%s' "$out" | sed -E 's/\x1b\[[0-9;]*m//g')
      plain="${plain%"${plain##*[![:space:]]}"}"
      [ "${plain##* }" = "$folder" ] && continue
      out=$(cut_name "$out" right)
      ;;
  esac
  result="$result$out"
done
result="${result%"${result##*[![:space:]]}"}"

if [ -z "$result" ]; then
  render_fallback
  print_stats
  exit 0
fi

printf '%s' "$result"
print_stats
