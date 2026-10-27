#!/bin/sh
# A re-run of install.sh shows only the links that changed.
#
# `stow -v --restow` plans an UNLINK of every link and then a LINK of each
# again, tagged "(reverts previous action)". Nothing changes on disk, but -v
# printed both, so every run of install.sh scrolled about 60 lines of no-ops
# past the user. quiet_restow drops those pairs and keeps everything else: a
# new link, a removed one, and stow's errors.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

# ── Static: the loop's stow call goes through the filter ──────
loop="$(sed -n '/^for pkg in /,/^done$/p' "$INST")"
assert_contains "$loop" '--restow "$pkg" 2>&1 | quiet_restow' \
  "the stow loop pipes stow's output (stderr included) through quiet_restow"
assert_contains "$(sed -n '1,5p' "$INST")" "set -euo pipefail" \
  "install.sh runs with pipefail, so a stow failure still stops it through the pipe"

if ! command -v stow >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
  echo "  skip: stow and bash are both needed for the behavioural checks"
  finish
fi

FN="$(awk '/^quiet_restow\(\) \{$/,/^}$/' "$INST")"
[ -n "$FN" ] || { fail "install.sh defines quiet_restow() at column 0 (extractable)"; finish; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/repo/pkg/.config/demo" "$T/home"
echo a >"$T/repo/pkg/.config/demo/a.conf"
echo b >"$T/repo/pkg/.config/demo/with space.conf"

# restow: the loop's own command, as install.sh runs it.
restow() {
  ( cd "$T/repo" && bash -c "set -euo pipefail
    $FN
    stow -v --no-folding --target=\"$T/home\" --restow pkg 2>&1 | quiet_restow" )
}

out="$(restow)"
assert_contains "$out" "LINK: .config/demo/a.conf" "a first run shows each new link"
assert_contains "$out" "LINK: .config/demo/with space.conf" "a path with a space shows too"

out="$(restow)"; rc=$?
assert_eq "$rc" 0 "a re-run succeeds"
assert_eq "$out" "" "a re-run with nothing to change prints nothing"
raw="$(cd "$T/repo" && stow -v --no-folding --target="$T/home" --restow pkg 2>&1)"
assert_contains "$raw" "(reverts previous action)" \
  "control: unfiltered, the same re-run prints the no-op pairs"

echo c >"$T/repo/pkg/.config/demo/c.conf"
out="$(restow)"
assert_contains "$out" "LINK: .config/demo/c.conf" "a file added to the package shows as a new link"
assert_not_contains "$out" "a.conf" "the links that didn't change stay hidden"
assert_not_contains "$out" "with space.conf" "an unchanged path with a space stays hidden"

# A link the package no longer provides: stow's restow unlinks it, and nothing
# links it back, so the UNLINK is real and stays.
rm "$T/repo/pkg/.config/demo/c.conf"
out="$(restow)"
assert_contains "$out" "UNLINK: .config/demo/c.conf" "a link stow removes still shows"
assert_not_contains "$out" "a.conf" "the links that didn't change stay hidden then too"

# A real file in the way: stow refuses, its error gets through the filter, and
# pipefail carries the failure out.
rm "$T/home/.config/demo/a.conf"; echo local >"$T/home/.config/demo/a.conf"
out="$(restow)"; rc=$?
[ "$rc" -ne 0 ] && pass "stow's failure still fails the command" \
  || fail "stow's failure still fails the command (rc=$rc)"
assert_contains "$out" "a.conf" "stow's error names the conflicting file"

finish
