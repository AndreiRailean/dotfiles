#!/bin/sh
# On macOS the herdr auto-layout daemon runs as a launchd agent — there is no
# systemd, and install.sh used to just print "start it yourself", so on a Mac
# new worktrees were never arranged. The plist is generated with this machine's
# paths because launchd expands neither ~ nor $HOME.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

FN="$(sed -n '/^herdr_autolayout_plist() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found herdr_autolayout_plist in install.sh" || fail "found herdr_autolayout_plist in install.sh"
LABEL="$(sed -n 's/^HERDR_AUTOLAYOUT_LABEL="\(.*\)"$/\1/p' "$INST")"
[ -n "$LABEL" ] && pass "install.sh names the launchd label" || fail "install.sh names the launchd label"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
OUT="$T/agent.plist"
HOME="/Users/tester" XDG_STATE_HOME= HERDR_AUTOLAYOUT_LABEL="$LABEL" bash -c "$FN
herdr_autolayout_plist" >"$OUT"
P="$(cat "$OUT")"

assert_contains "$P" "<string>$LABEL</string>" "plist carries the label"
assert_contains "$P" "<string>/Users/tester/.config/herdr/scripts/herdr-autolayout</string>" "runs the stowed script by absolute path"
assert_contains "$P" "/opt/homebrew/bin" "PATH reaches Homebrew's herdr"
assert_contains "$P" "/Users/tester/.local/bin" "PATH reaches ~/.local/bin's herdr"
assert_contains "$P" "/Users/tester/.local/state/herdr/autolayout.launchd.log" "stderr goes to the XDG state dir"
assert_not_contains "$P" '$HOME' "no unexpanded \$HOME"
assert_not_contains "$P" '~/' "no ~ paths (launchd doesn't expand them)"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$OUT" >/dev/null && pass "plist is valid (plutil -lint)" || fail "plist is valid (plutil -lint)"
else
  echo "  skip: plutil unavailable (plist validation)"
fi

# doctor.sh looks for the same label install.sh loads.
grep -qF "gui/\$(id -u)/$LABEL" "$REPO/doctor.sh" && pass "doctor.sh checks the same label" \
  || fail "doctor.sh checks the same label"

finish
