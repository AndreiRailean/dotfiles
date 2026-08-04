#!/bin/sh
# lazygit package: the binary is installed by install.sh (package manager first,
# upstream release tarball as fallback), the config pins the intended settings,
# lazygit's own state stays out of the repo, and the package is wired into
# install.sh / doctor.sh.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"

# ── install.sh: the install block ────────────────────────────
INST="$REPO/install.sh"

grep -q 'command -v lazygit' "$INST" \
  && pass "install.sh guards on lazygit already being present" \
  || fail "install.sh guards on lazygit already being present"

grep -q 'pkg_install lazygit' "$INST" \
  && pass "install.sh tries the system package" \
  || fail "install.sh tries the system package"

grep -q 'install_lazygit_release' "$INST" \
  && pass "install.sh has a release fallback" \
  || fail "install.sh has a release fallback"

# Upstream publishes lazygit_<version>_<Os>_<Arch>.tar.gz; the asset carries the
# version WITHOUT the tag's leading v. Getting this string wrong makes the
# fallback dead weight on the one platform that needs it (Ubuntu LTS, where
# lazygit is absent from the archive entirely).
grep -q 'jesseduffield/lazygit/releases/download' "$INST" \
  && pass "release fallback points at the upstream download URL" \
  || fail "release fallback points at the upstream download URL"

grep -q 'lazygit_${ver}_${os}_${arch}.tar.gz' "$INST" \
  && pass "release asset name matches upstream's naming" \
  || fail "release asset name matches upstream's naming"

# Best-effort: a failed install must warn, not abort the run.
grep -q '!! lazygit install failed' "$INST" \
  && pass "lazygit install failure warns instead of aborting" \
  || fail "lazygit install failure warns instead of aborting"

# ── Ordering: lazygit before the auto-layout daemon ──────────
# The daemon enabled at the end of install.sh runs lazygit in every new
# worktree's second tab; installing it afterwards leaves a fresh machine with a
# tab that dies on launch.
lg_line="$(grep -n 'command -v lazygit' "$INST" | head -1 | cut -d: -f1)"
al_line="$(grep -n 'herdr-autolayout.service' "$INST" | head -1 | cut -d: -f1)"
if [ -n "$lg_line" ] && [ -n "$al_line" ] && [ "$lg_line" -lt "$al_line" ]; then
  pass "lazygit is installed before the auto-layout daemon is enabled"
else
  fail "lazygit is installed before the auto-layout daemon is enabled (lazygit@${lg_line:-?} autolayout@${al_line:-?})"
fi

bash -n "$INST" && pass "install.sh parses" || fail "install.sh parses"

finish
