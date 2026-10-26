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
grep -q '^sidebar_width = ' "$CONF" && pass "sidebar width pinned" || fail "sidebar width pinned"

# Runtime state is git-ignored (doctor.sh relies on this to skip it)
for f in herdr.log herdr.sock session.json .plugins.lock release-notes.json session-snapshots/session-0.json; do
  if git -C "$REPO" check-ignore -q "herdr/.config/herdr/$f"; then
    pass "git-ignored: $f"
  else
    fail "git-ignored: $f"
  fi
done

# Wired into the package machinery
grep -Eq 'for pkg in .*\bherdr\b' "$REPO/install.sh" && pass "install.sh stows herdr" || fail "install.sh stows herdr"
grep -Eq 'PACKAGES=.*\bherdr\b' "$REPO/doctor.sh" && pass "doctor.sh scans herdr" || fail "doctor.sh scans herdr"
grep -q 'update.sh" --missing' "$REPO/install.sh" && grep -q 'DEFAULT_TOOLS=.*\bherdr\b' "$REPO/update.sh" \
  && pass "install.sh bootstraps herdr through update.sh" || fail "install.sh bootstraps herdr through update.sh"

# The auto-layout daemon is retired: nothing installs it, and install.sh stops
# a copy an earlier run left behind (docs/adr/20261026-drop-herdr-autolayout.md).
[ ! -e "$REPO/herdr/.config/systemd" ] && [ ! -e "$REPO/herdr/.config/herdr/scripts" ] \
  && pass "the herdr package ships no daemon" || fail "the herdr package ships no daemon"
grep -q 'enable --now herdr-autolayout' "$REPO/install.sh" \
  && fail "install.sh no longer enables the auto-layout unit" || pass "install.sh no longer enables the auto-layout unit"
grep -q 'systemctl --user stop herdr-autolayout.service' "$REPO/install.sh" \
  && pass "install.sh stops a leftover auto-layout unit" || fail "install.sh stops a leftover auto-layout unit"
grep -q 'launchctl bootout "gui/$(id -u)/dotfiles.herdr-autolayout"' "$REPO/install.sh" \
  && pass "install.sh unloads a leftover launchd agent" || fail "install.sh unloads a leftover launchd agent"
grep -q 'herdr.dev/install.sh' "$REPO/update.sh" && pass "update.sh knows herdr's installer" || fail "update.sh knows herdr's installer"

# Scripts still parse
bash -n "$REPO/install.sh" && pass "install.sh parses" || fail "install.sh parses"
bash -n "$REPO/doctor.sh" && pass "doctor.sh parses" || fail "doctor.sh parses"

finish
