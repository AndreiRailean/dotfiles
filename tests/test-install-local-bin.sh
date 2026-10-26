#!/bin/sh
# install.sh must create ~/.local/bin before any installer is pointed at it.
#
# Starship's official installer refuses a -b BIN_DIR that doesn't exist yet
# ("Installation location … does not appear to be a directory") and exits 1.
# On a brand-new Mac nothing has created ~/.local/bin by that point, so the
# installer fails with a red error and install.sh silently falls through to
# `brew install starship` instead. path.sh also only adds ~/.local/bin to PATH
# when the directory exists, so creating it up front matters beyond starship.
#
# Starship now comes from update.sh, which creates the directory it installs
# into, but path.sh's reason still holds — so the anchor is the update.sh call.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

mk_line="$(grep -n 'mkdir -p "\$HOME/.local/bin"' "$INST" | head -1 | cut -d: -f1)"
use_line="$(grep -n 'update.sh" --missing' "$INST" | head -1 | cut -d: -f1)"

if [ -z "$use_line" ]; then
  fail "found the update.sh --missing call in install.sh"
elif [ -n "$mk_line" ] && [ "$mk_line" -lt "$use_line" ]; then
  pass "~/.local/bin is created (line $mk_line) before update.sh --missing (line $use_line)"
else
  fail "~/.local/bin must be created before update.sh --missing (line $use_line); mkdir at line ${mk_line:-none}"
fi

finish
