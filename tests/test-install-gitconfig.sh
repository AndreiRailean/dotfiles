#!/bin/sh
# install.sh must seed an empty ~/.gitconfig so `git config --global` writes
# stay out of the repo.
#
# Without ~/.gitconfig, git's --global target is ~/.config/git/config — the
# tracked, symlinked file — so 1Password's commit-signing setup wrote a
# macOS-only op-ssh-sign path into the shared config.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }
command -v git >/dev/null 2>&1 || { echo "  skip: git needed"; finish; }

FN="$(sed -n '/^seed_global_gitconfig() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found seed_global_gitconfig in install.sh" || fail "found seed_global_gitconfig in install.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
H="$T/home"
mkdir -p "$H/.config/git"
: >"$T/tracked-config"
ln -s "$T/tracked-config" "$H/.config/git/config"   # stands in for the stow link

HOME="$H" bash -c "$FN
seed_global_gitconfig" >/dev/null
[ -f "$H/.gitconfig" ] && pass "missing ~/.gitconfig is created" || fail "missing ~/.gitconfig is created"

HOME="$H" XDG_CONFIG_HOME= GIT_CONFIG_NOSYSTEM=1 git config --global gpg.format ssh
assert_eq "$(cat "$T/tracked-config")" "" "git config --global no longer writes the tracked file"
assert_contains "$(cat "$H/.gitconfig")" "format = ssh" "git config --global writes ~/.gitconfig"

printf '[user]\n\tname = Someone\n' >"$H/.gitconfig"
HOME="$H" bash -c "$FN
seed_global_gitconfig" >/dev/null
assert_eq "$(cat "$H/.gitconfig")" "$(printf '[user]\n\tname = Someone')" "existing ~/.gitconfig is left alone"

finish
