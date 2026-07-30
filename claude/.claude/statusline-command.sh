#!/bin/bash
# Status line: render the user's ACTUAL starship prompt (~/.config/starship.toml)
# by invoking the real `starship` binary, rather than hand-porting the config
# into a separate implementation that could drift from it. This guarantees
# the status line always matches what the terminal shows, including future
# starship.toml edits.
#
# Falls back to a plain colored `user@host:cwd` (derived from the ~/.bashrc
# PS1 fallback) if starship can't be found or produces no output, so the
# status line degrades instead of going blank.

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd=$(pwd)

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
  exit 0
fi

# Approximation: the JSON payload has no terminal width field, so fall back
# to $COLUMNS (often unset for non-interactive invocations) or 80.
width="${COLUMNS:-80}"

# --path/--logical-path (both) + PWD (both) are required: the `directory`
# module renders off the logical PWD, and `--path` alone renders whatever
# directory this script happens to execute in, not Claude Code's cwd.
# STARSHIP_SHELL must be unset, or starship wraps every color code in bash
# readline markers (\[ \]) that a status line would print literally.
raw=$(env -u STARSHIP_SHELL PWD="$cwd" "$STARSHIP" prompt \
  --path "$cwd" --logical-path "$cwd" --status 0 --jobs 0 -w "$width" 2>/dev/null)

if [ -z "$raw" ]; then
  render_fallback
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
  exit 0
fi

printf '%s' "$result"
