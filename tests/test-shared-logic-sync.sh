#!/bin/sh
# install.sh and doctor.sh duplicate logic on purpose. This keeps the copies
# honest until someone extracts a shared library.
#
# WHY THIS FILE EXISTS: the two scripts share no shell library, so several
# pieces of knowledge live in both — the package list, owned_roots, the lazygit
# version floor, stow's flag set, how the repo root is derived. Nothing enforces
# that, and the failures are silent: doctor.sh reporting a package install.sh
# never stowed, or a floor check that passes in one script and fails in the
# other. It has already cost a real bug — install.sh derived the repo root with
# `pwd` while doctor.sh used `pwd -P`, which made link pruning a silent no-op
# whenever ~/dotfiles was itself a symlink (see docs/adr/20260805-no-shared-shell-library.md).
#
# So each assertion below is a copy-pair that must stay in step. Every failure
# here is also a reason to reach for the extraction described in that ADR:
# the more of these there are, the weaker the case for keeping them apart.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"
DOC="$REPO/doctor.sh"

# ── The package list ──────────────────────────────────────────
# install.sh stows these; doctor.sh scans them. A package in one and not the
# other is invisible: either stowed but never checked for drift, or reported as
# "not linked into $HOME" forever because nothing ever links it.
i_pkgs="$(sed -n 's/^for pkg in \(.*\); do$/\1/p' "$INST")"
d_pkgs="$(sed -n 's/^PACKAGES="\(.*\)"$/\1/p' "$DOC")"
[ -n "$i_pkgs" ] && pass "found install.sh's package list" \
  || fail "found install.sh's package list (pattern no longer matches)"
[ -n "$d_pkgs" ] && pass "found doctor.sh's PACKAGES" \
  || fail "found doctor.sh's PACKAGES (pattern no longer matches)"
assert_eq "$i_pkgs" "$d_pkgs" "install.sh and doctor.sh agree on the package list"

# ── owned_roots ───────────────────────────────────────────────
# Both derive "the top directory a package introduces under $HOME" to decide
# which trees they may touch. install.sh prunes dead links inside them, doctor.sh
# reports untracked files inside them — so a divergence means one script acts on
# a tree the other doesn't know about. Compared byte-for-byte: these are copies,
# not merely similar, and any intentional edit belongs in both.
i_or="$(awk '/^owned_roots\(\)/,/^}/' "$INST")"
d_or="$(awk '/^owned_roots\(\)/,/^}/' "$DOC")"
[ -n "$i_or" ] && pass "found install.sh's owned_roots()" \
  || fail "found install.sh's owned_roots() (not at column 0?)"
[ -n "$d_or" ] && pass "found doctor.sh's owned_roots()" \
  || fail "found doctor.sh's owned_roots() (not at column 0?)"
assert_eq "$i_or" "$d_or" "the two owned_roots() bodies are identical"

# ── The lazygit version floor ─────────────────────────────────
# install.sh upgrades anything below the floor; doctor.sh reports it. Both parse
# `lazygit --version` with the same fiddly sed (the greedy-match trap: the line
# ends with git's OWN version, so the match is anchored on `, os=`). If only one
# copy is corrected, one script silently disagrees with the other about whether
# the machine is healthy.
i_re="$(grep -o 'version=\[\^0-9\].*os=\.\*/\\1/p' "$INST")"
d_re="$(grep -o 'version=\[\^0-9\].*os=\.\*/\\1/p' "$DOC")"
[ -n "$i_re" ] && pass "found the version-parsing sed in install.sh" \
  || fail "found the version-parsing sed in install.sh"
assert_eq "$i_re" "$d_re" "both scripts parse lazygit --version identically"

i_floor="$(grep -o '\$minor" -ge [0-9]*' "$INST" | grep -o '[0-9]*$')"
d_floor="$(grep -o '\$lg_minor" -lt [0-9]*' "$DOC" | grep -o '[0-9]*$')"
[ -n "$i_floor" ] && pass "found install.sh's floor constant" \
  || fail "found install.sh's floor constant"
[ -n "$d_floor" ] && pass "found doctor.sh's floor constant" \
  || fail "found doctor.sh's floor constant"
assert_eq "$i_floor" "$d_floor" "both scripts use the same lazygit minor-version floor"

# ── How the repo root is derived ──────────────────────────────
# `pwd -P` in both, and identical. install.sh compares resolved symlink targets
# against this value, and stow writes those links via the repo's PHYSICAL path
# (verified in test-install-prune-dead-links.sh), so a logical `pwd` here breaks
# pruning silently rather than loudly.
i_dd="$(grep -m1 '^DOTFILES_DIR=' "$INST")"
d_dd="$(grep -m1 '^DOTFILES_DIR=' "$DOC")"
[ -n "$i_dd" ] && pass "found both DOTFILES_DIR derivations" \
  || fail "found both DOTFILES_DIR derivations"
assert_eq "$i_dd" "$d_dd" "install.sh and doctor.sh derive DOTFILES_DIR identically"

# ── stow's flag set ───────────────────────────────────────────
# doctor.sh --adopt re-stows after moving files into the repo. --no-folding is
# the load-bearing one: drop it there and stow would replace a per-file-symlink
# directory with a single directory symlink, quietly changing the layout every
# other part of this repo (and these tests) assumes.
i_flags="$(grep -o '\-\-no-folding --target="\$HOME" --restow "\$pkg"' "$INST")"
d_flags="$(grep -o '\-\-no-folding --target="\$HOME" --restow "\$pkg"' "$DOC")"
[ -n "$i_flags" ] && pass "found install.sh's stow flags" \
  || fail "found install.sh's stow flags"
assert_eq "$i_flags" "$d_flags" "both scripts invoke stow with the same flags"

# ── The .pre-dotfiles.* contract ──────────────────────────────
# Not shared code but a shared NAME: install.sh writes the displaced file,
# doctor.sh skips it. Renaming the suffix in one place makes doctor.sh start
# offering to adopt those backups into the repo — which commits them. Producer
# and consumer are asserted separately so a rename can't half-land.
assert_contains "$(cat "$INST")" '.pre-dotfiles.' \
  "install.sh still writes the .pre-dotfiles.* backup (producer)"
assert_contains "$(cat "$DOC")" '.pre-dotfiles.' \
  "doctor.sh still skips the .pre-dotfiles.* backup (consumer)"

# ── The ADR that explains all of the above ────────────────────
ADR="$REPO/docs/adr/20260805-no-shared-shell-library.md"
[ -f "$ADR" ] && pass "the ADR recording this decision exists" \
  || fail "the ADR recording this decision exists ($ADR)"

finish
