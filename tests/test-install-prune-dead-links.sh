#!/bin/sh
# Deleting a tracked file must not leave manual cleanup on every other machine.
#
# THE PROBLEM: removing a file from a package (8fcfba8 dropped the tmux
# agent-* scripts) turns every machine's symlink to it into a dangling link.
# `stow --restow` does NOT clean those up — stow unlinks only what the package
# CURRENTLY contains, so a link whose repo file is gone is invisible to it.
# The link therefore survives every later install, and doctor.sh reports it as
# drift forever. One machine's `git rm` becomes a chore on all the others,
# which is the opposite of what a dotfiles repo is for.
#
# So install.sh prunes them. The scope has to stay narrow, because this deletes
# things in $HOME: only a symlink that is (a) dangling, (b) inside a directory
# one of our packages owns, and (c) pointing back INTO this repo. A broken link
# the user made themselves, or one aimed anywhere else, is not ours to remove.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

# ── Static: the stow loop prunes, and does so after stowing ───
loop="$(sed -n '/^for pkg in /,/^done$/p' "$INST")"
assert_contains "$loop" "prune_dead_links" "stow loop prunes dead links"

# After stow, not before: --restow unlinks and relinks, so pruning first would
# inspect links stow is about to recreate anyway.
p_line="$(printf '%s\n' "$loop" | grep -n 'prune_dead_links' | head -1 | cut -d: -f1)"
s_line="$(printf '%s\n' "$loop" | grep -n '^[[:space:]]*stow -' | head -1 | cut -d: -f1)"
if [ -n "$p_line" ] && [ -n "$s_line" ] && [ "$p_line" -gt "$s_line" ]; then
  pass "pruning runs after the stow call"
else
  fail "pruning runs after the stow call (prune=$p_line stow=$s_line)"
fi

if ! command -v stow >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
  echo "  skip: stow and bash are both needed for the behavioural checks"
  finish
fi

# Extract the real implementation rather than a paraphrase of it.
FNS="$(awk '/^link_target_abs\(\)/,/^}/' "$INST")
$(awk '/^owned_roots\(\)/,/^}/' "$INST")
$(awk '/^prune_dead_links\(\)/,/^}/' "$INST")"
for fn in link_target_abs owned_roots prune_dead_links; do
  case "$FNS" in
    *"$fn()"*) pass "install.sh defines $fn() at column 0 (extractable)" ;;
    *) fail "install.sh defines $fn() at column 0 (extractable)"; finish ;;
  esac
done

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

# The repo has to sit INSIDE the fake $HOME, as it really does (~/dotfiles):
# stow writes relative links, so how many `..` hops reach the repo — and
# therefore whether the target resolves back into it — depends on that nesting.
# A sibling layout would make every link resolve outside the repo and the
# safety check would (correctly) refuse to prune anything.
#
# A package owning .config/demo, mirroring the tmux layout: one tracked file at
# the root of the owned tree, and the dead links one level down in a subdir the
# repo no longer has at all.
mkdir -p "$T/home/dotfiles/pkg/.config/demo"
printf 'tracked\n' >"$T/home/dotfiles/pkg/.config/demo/demo.conf"
mkdir -p "$T/home/.config/demo/scripts"

# (a) the dead link: points into the repo at a file that no longer exists,
#     written relative exactly the way stow writes it.
ln -s "../../../dotfiles/pkg/.config/demo/scripts/gone" "$T/home/.config/demo/scripts/gone"
# (b) a dangling link aimed OUTSIDE the repo — not ours, must survive.
ln -s "/nonexistent/elsewhere" "$T/home/.config/demo/scripts/foreign"
# (c) a real file in the owned tree — must survive.
printf 'mine\n' >"$T/home/.config/demo/scripts/keep.txt"

run_prune() {
  ( cd "$T/home/dotfiles" && HOME="$T/home" DOTFILES_DIR="$T/home/dotfiles" bash -c "$FNS
    prune_dead_links pkg" 2>&1 )
}

# Control: stow alone leaves the dead link in place. Without this the test
# could pass for the wrong reason — stow having handled it all along.
( cd "$T/home/dotfiles" && stow --no-folding --target="$T/home" --restow pkg ) >/dev/null 2>&1
if [ -L "$T/home/.config/demo/scripts/gone" ]; then
  pass "control: stow --restow does not remove the dead link"
else
  fail "control: stow --restow does not remove the dead link (nothing left to prune)"
fi

out="$(run_prune)"

if [ -L "$T/home/.config/demo/scripts/gone" ]; then
  fail "the dead link into the repo is removed (output: $out)"
else
  pass "the dead link into the repo is removed"
fi
assert_contains "$out" "gone" "the removal is reported, not silent"

# The safety boundary — the whole reason the target is checked at all.
if [ -L "$T/home/.config/demo/scripts/foreign" ]; then
  pass "a dangling link pointing outside the repo is left alone"
else
  fail "a dangling link pointing outside the repo is left alone"
fi
assert_eq "$(cat "$T/home/.config/demo/scripts/keep.txt" 2>/dev/null)" "mine" \
  "an untracked real file in the owned tree is left alone"
if [ -L "$T/home/.config/demo/demo.conf" ] && [ -e "$T/home/.config/demo/demo.conf" ]; then
  pass "the package's live link is left alone"
else
  fail "the package's live link is left alone"
fi

# The subdir still holds foreign + keep.txt, so it must NOT be removed.
if [ -d "$T/home/.config/demo/scripts" ]; then
  pass "a directory that still has contents is kept"
else
  fail "a directory that still has contents is kept"
fi

# Idempotent: a second pass has nothing to say and breaks nothing.
out2="$(run_prune)"
assert_not_contains "$out2" "Removed" "a second pass prunes nothing further"

# Now the empty-directory case: once the last dead link goes, the directory
# that existed only to hold it is clutter that doctor.sh would keep scanning.
rm -f "$T/home/.config/demo/scripts/foreign" "$T/home/.config/demo/scripts/keep.txt"
ln -s "../../../dotfiles/pkg/.config/demo/scripts/gone2" "$T/home/.config/demo/scripts/gone2"
run_prune >/dev/null
if [ -d "$T/home/.config/demo/scripts" ]; then
  fail "a directory left empty by pruning is removed"
else
  pass "a directory left empty by pruning is removed"
fi
# ...but never the owned root itself, which stow needs on the next run.
if [ -d "$T/home/.config/demo" ]; then
  pass "the owned root itself survives"
else
  fail "the owned root itself survives"
fi

# ── The repo reached through a symlink ────────────────────────
# stow resolves the package dir PHYSICALLY: with ~/dotfiles a symlink to some
# other path, the links it writes point at the real location. So DOTFILES_DIR
# must be physical too (`pwd -P`), or the target comparison never matches and
# pruning becomes a silent no-op on exactly those machines. Verified by
# experiment, not assumed — stow wrote ../../real/pkg/… not ../dotfiles/pkg/….
assert_contains "$(grep -m1 'DOTFILES_DIR=' "$INST")" "pwd -P" \
  "install.sh derives DOTFILES_DIR physically"
assert_contains "$(grep -m1 'DOTFILES_DIR=' "$REPO/doctor.sh")" "pwd -P" \
  "doctor.sh derives DOTFILES_DIR physically (the two must agree)"

S="$T/sym"
mkdir -p "$S/real/pkg/.config/demo/scripts" "$S/home"
printf 'tracked\n' >"$S/real/pkg/.config/demo/demo.conf"
printf 'doomed\n' >"$S/real/pkg/.config/demo/scripts/gone"
ln -s "$S/real" "$S/home/dotfiles"          # the repo, behind a symlink
# Let stow write the link, then delete the repo file — the actual `git rm`
# sequence. Hand-writing the relative target means counting `..` hops against
# the symlink, which is the very thing under test; stow's own output can't be
# wrong about it.
( cd "$S/home/dotfiles" && stow --no-folding --target="$S/home" --restow pkg ) >/dev/null 2>&1
rm -f "$S/real/pkg/.config/demo/scripts/gone"
if [ -L "$S/home/.config/demo/scripts/gone" ] && [ ! -e "$S/home/.config/demo/scripts/gone" ]; then
  pass "setup: stow's own link now dangles, and points via the repo's real path"
else
  fail "setup: stow's own link now dangles (got: $(readlink "$S/home/.config/demo/scripts/gone" 2>&1))"
fi
# DOTFILES_DIR exactly as install.sh derives it — the real assignment line, run
# from a script invoked THROUGH the symlink so BASH_SOURCE[0] is what it would
# be in a genuine `~/dotfiles/install.sh` run. Recomputing it here with our own
# `pwd -P` would test the test, not the script.
grep -m1 '^DOTFILES_DIR=' "$INST" >"$S/home/dotfiles/dd-probe.sh"
printf 'printf "%%s\\n" "$DOTFILES_DIR"\n' >>"$S/home/dotfiles/dd-probe.sh"
sym_dd="$(bash "$S/home/dotfiles/dd-probe.sh")"
( cd "$S/home/dotfiles" && HOME="$S/home" DOTFILES_DIR="$sym_dd" bash -c "$FNS
  prune_dead_links pkg" ) >/dev/null 2>&1
if [ -L "$S/home/.config/demo/scripts/gone" ]; then
  fail "pruning still works when the repo is reached through a symlink"
else
  pass "pruning still works when the repo is reached through a symlink"
fi

# ── doctor.sh should name the fix, not just the symptom ────────
assert_contains "$(sed -n '/Broken symlinks/,+3p' "$REPO/doctor.sh")" "install.sh" \
  "doctor.sh points at ./install.sh as the fix for broken symlinks"

finish
