#!/bin/sh
# herdr package: config.toml is valid and pins the intended settings, runtime
# state is git-ignored, and herdr is wired into install.sh / doctor.sh.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
CONF="$REPO/herdr/.config/herdr/config.toml"

# Config file present
[ -f "$CONF" ] && pass "config.toml exists" || fail "config.toml exists"

# Valid TOML (skip if no python3 tomllib available)
if command -v python3 >/dev/null 2>&1 && python3 -c 'import tomllib' 2>/dev/null; then
  if python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$CONF" 2>/dev/null; then
    pass "config.toml is valid TOML"
  else
    fail "config.toml is valid TOML"
  fi
else
  echo "  skip: python3 tomllib unavailable (TOML validation)"
fi

# Pins the three intended settings
grep -q '^onboarding = false' "$CONF" && pass "onboarding disabled" || fail "onboarding disabled"
grep -q 'name = "tokyo-night"' "$CONF" && pass "theme tokyo-night" || fail "theme tokyo-night"
grep -q 'prefix = "ctrl+a"' "$CONF" && pass "prefix ctrl+a" || fail "prefix ctrl+a"

# Runtime state is git-ignored (doctor.sh relies on this to skip it)
for f in herdr.log herdr.sock session.json .plugins.lock release-notes.json; do
  if git -C "$REPO" check-ignore -q "herdr/.config/herdr/$f"; then
    pass "git-ignored: $f"
  else
    fail "git-ignored: $f"
  fi
done

# Wired into the package machinery
grep -Eq 'for pkg in .*\bherdr\b' "$REPO/install.sh" && pass "install.sh stows herdr" || fail "install.sh stows herdr"
grep -Eq 'PACKAGES=.*\bherdr\b' "$REPO/doctor.sh" && pass "doctor.sh scans herdr" || fail "doctor.sh scans herdr"
grep -q 'herdr.dev/install.sh' "$REPO/install.sh" && pass "install.sh bootstraps herdr" || fail "install.sh bootstraps herdr"

# Scripts still parse
bash -n "$REPO/install.sh" && pass "install.sh parses" || fail "install.sh parses"
bash -n "$REPO/doctor.sh" && pass "doctor.sh parses" || fail "doctor.sh parses"

finish
