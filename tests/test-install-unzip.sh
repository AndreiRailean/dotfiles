#!/bin/sh
# install.sh installs unzip before anything that needs it.
#
# update.sh unpacks fnm and deno with unzip, and install.sh itself unzips the
# Nerd Font and win32yank. Ubuntu's cloud images ship without unzip: on a fresh
# 26.04 VM, fnm's install failed for lack of it. Under `set -e`, the win32yank
# unzip would have stopped the whole install on a WSL box without it.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

at() { grep -n "$1" "$INST" | head -1 | cut -d: -f1; }

ensure="$(at '^ensure_tool unzip unzip')"
[ -n "$ensure" ] && pass "install.sh installs unzip" || fail "install.sh installs unzip"
ensure="${ensure:-999999}"

# Every unzip call, and the update.sh run that unzips fnm/deno, comes after it.
for n in $(grep -n '^[^#]*unzip -' "$INST" | cut -d: -f1); do
  [ "$n" -gt "$ensure" ] && pass "unzip on line $n runs after it is installed" \
    || fail "unzip on line $n runs before ensure_tool unzip (line $ensure)"
done
missing="$(at 'update.sh" --missing')"
[ -n "$missing" ] && [ "$missing" -gt "$ensure" ] \
  && pass "update.sh --missing runs after unzip is installed" \
  || fail "update.sh --missing runs after unzip is installed"

finish
