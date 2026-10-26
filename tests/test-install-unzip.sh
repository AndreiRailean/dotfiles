#!/bin/sh
# install.sh installs unzip before anything that needs it, and update.sh says
# so when it's missing.
#
# update.sh unpacks fnm and deno with unzip, and install.sh itself unzips the
# Nerd Font and win32yank. Ubuntu's cloud images ship without unzip: on a fresh
# 26.04 VM, fnm's install failed for lack of it. Under `set -e`, the win32yank
# unzip would have stopped the whole install on a WSL box without it.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"
UPD="$REPO/update.sh"

at() { grep -n "$1" "$INST" | head -1 | cut -d: -f1; }

defined="$(at '^ensure_tool() {')"
ensure="$(at '^ensure_tool unzip unzip')"
[ -n "$ensure" ] && pass "install.sh installs unzip" || fail "install.sh installs unzip"
ensure="${ensure:-999999}"
[ -n "$defined" ] && [ "$ensure" -gt "$defined" ] \
  && pass "ensure_tool unzip comes after ensure_tool is defined" \
  || fail "ensure_tool unzip comes after ensure_tool is defined (line ${defined:-?})"

# Every line that runs unzip, in any form: not a comment, and `unzip` as a
# command word (start of line or after a space, ;, &, |, ( or `), whatever
# follows. The ensure_tool line itself is the one exception.
calls="$(grep -nE '(^|[[:space:];&|(`])unzip([[:space:];)]|$)' "$INST" \
  | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'ensure_tool unzip unzip' | cut -d: -f1)"
[ -n "$calls" ] && pass "found install.sh's unzip calls" || fail "found install.sh's unzip calls"
for n in $calls; do
  [ "$n" -gt "$ensure" ] && pass "unzip on line $n runs after it is installed" \
    || fail "unzip on line $n runs before ensure_tool unzip (line $ensure)"
done

# update.sh unzips fnm and deno; both of its install paths run after unzip.
for mode in --missing --ask; do
  n="$(at "update.sh\" $mode")"
  [ -n "$n" ] && [ "$n" -gt "$ensure" ] \
    && pass "update.sh $mode runs after unzip is installed" \
    || fail "update.sh $mode runs after unzip is installed"
done

# A machine whose last install.sh run predates unzip can still run update.sh
# --add directly. Every installer there that unzips checks for it first, so it
# says what to do rather than dying on "unzip: command not found".
for fn in $(awk '/^install_[a-z]+\(\) \{$/ { f = $1; sub(/\(\)/, "", f) }
                 f && /(^|[[:space:]])unzip[[:space:]]/ { print f }
                 /^\}$/ { f = "" }' "$UPD" | sort -u); do
  body="$(sed -n "/^$fn() {\$/,/^}\$/p" "$UPD")"
  assert_contains "$body" "needs_unzip" "update.sh's $fn checks for unzip before using it"
done

finish
