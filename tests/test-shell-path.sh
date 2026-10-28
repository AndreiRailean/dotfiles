#!/bin/sh
# path.sh's path_prepend must MOVE an entry that is already on PATH to the
# front, not skip it.
#
# On macOS, /etc/zprofile runs path_helper in every zsh login shell, which puts
# /usr/bin & co. first and demotes the PATH it inherited. A nested shell (herdr
# or tmux pane) therefore starts with ~/.local/bin present but behind /usr/bin;
# the old skip-if-present check left it there, so `vim` in scripts resolved to
# the system vim rather than the ~/.local/bin/vim -> nvim link.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
PATHSH="$REPO/shell/.config/shell/path.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/home/.local/bin" "$T/home/bin"
H="$T/home"

# A stand-in Homebrew prefix. The checks below point HOMEBREW_PREFIX away from
# it (and from a real /opt/homebrew on a Mac) unless they're about Homebrew.
mkdir -p "$T/brew/bin" "$T/brew/sbin"
printf '#!/bin/sh\n' >"$T/brew/bin/brew"; chmod +x "$T/brew/bin/brew"
NOBREW="$T/nobrew"

# run <shell> <PATH before> [prefix]: source path.sh twice (idempotence) and
# print PATH. keep: the same in the keep-order mode ~/.zshenv uses.
run() {
  HOME="$H" PATH="$2" HOMEBREW_PREFIX="${3:-$NOBREW}" \
    "$1" -c ". \"$PATHSH\"; . \"$PATHSH\"; printf '%s' \"\$PATH\""
}
keep() {
  HOME="$H" PATH="$2" HOMEBREW_PREFIX="${3:-$NOBREW}" _path_keep_order=1 \
    "$1" -c ". \"$PATHSH\"; . \"$PATHSH\"; printf '%s' \"\$PATH\""
}

for name in sh bash zsh; do
  # Absolute, because the PATHs under test don't necessarily contain it.
  sh="$(command -v "$name")" || { echo "  skip: $name not installed"; continue; }

  got="$(run "$sh" "/usr/bin:/bin")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/usr/bin:/bin" "$name: fresh PATH gets both dirs in front"

  # The path_helper case: already present, but demoted behind /usr/bin.
  got="$(run "$sh" "/usr/bin:/bin:$H/.local/bin:/opt/x")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/usr/bin:/bin:/opt/x" "$name: demoted entry is moved to the front"

  got="$(run "$sh" "$H/.local/bin:/usr/bin:$H/.local/bin:/bin:$H/.local/bin")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/usr/bin:/bin" "$name: every duplicate is removed"

  # Prefix-sharing entries must not be mangled by the removal.
  got="$(run "$sh" "$H/.local/bin2:/usr/bin")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$H/.local/bin2:/usr/bin" "$name: similarly named entry is left alone"

  got="$(HOME="$T/nohome" PATH="/usr/bin:/bin" HOMEBREW_PREFIX="$NOBREW" "$sh" -c ". \"$PATHSH\"; printf '%s' \"\$PATH\"")"
  assert_eq "$got" "/usr/bin:/bin" "$name: missing dirs are not added"

  # Homebrew: ahead of the system dirs, behind ~/.local/bin and ~/bin.
  got="$(run "$sh" "/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: Homebrew's bin and sbin come after ~/.local/bin and ~/bin"
  # path_helper's demotion in a login shell, which ~/.zprofile's line follows.
  got="$(run "$sh" "/usr/bin:/bin:$T/brew/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: a demoted Homebrew is moved back ahead of /usr/bin"
  # Only ahead of the system's dirs: brew's python and node mustn't jump a
  # venv or fnm put ahead of it, which a child zsh would otherwise inherit and
  # reorder through ~/.zshenv.
  got="$(run "$sh" "/venv/bin:/fnm/bin:/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/venv/bin:/fnm/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: Homebrew goes just ahead of /usr/bin, behind a venv and fnm"
  got="$(run "$sh" "/venv/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/venv/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: a Homebrew already ahead of /usr/bin is left where it is"
  got="$(run "$sh" "/opt/x" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/opt/x:$T/brew/bin:$T/brew/sbin" \
    "$name: with no /usr/bin, Homebrew goes last"
  # The first /usr/bin is the one that counts.
  got="$(run "$sh" "/usr/bin:$T/brew/bin:/x:/usr/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/x:/usr/bin" \
    "$name: Homebrew goes ahead of the first /usr/bin"
  # With no /usr/bin, a Homebrew already on PATH stays where it is.
  got="$(run "$sh" "$T/brew/bin:/opt/x" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:/opt/x:$T/brew/sbin" \
    "$name: with no /usr/bin, a Homebrew already there isn't moved"

  # Keep-order mode, which ~/.zshenv uses: a clean start (a command over SSH)
  # gets everything, in the same order a full run gives.
  got="$(keep "$sh" "/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: keep-order on a clean PATH gives the full order"
  # An inherited order is kept: nothing jumps the venv.
  got="$(keep "$sh" "/venv/bin:$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "/venv/bin:$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: keep-order leaves an inherited PATH as it is"
  # ~/.local/bin already there (an earlier line of ~/.zshenv, say) still gets
  # Homebrew: the SSH case this is for.
  got="$(keep "$sh" "$H/.local/bin:/usr/bin:/bin" "$T/brew")"
  assert_eq "$got" "$H/.local/bin:$H/bin:$T/brew/bin:$T/brew/sbin:/usr/bin:/bin" \
    "$name: keep-order still adds Homebrew when ~/.local/bin is already there"

  # A prefix with no brew in it (a stale HOMEBREW_PREFIX) adds nothing.
  mkdir -p "$T/stale/bin"
  got="$(run "$sh" "/usr/bin:/bin" "$T/stale")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/usr/bin:/bin" "$name: a prefix without brew is skipped"
done

# path_before with DIR and ANCHOR the same does nothing (HOMEBREW_PREFIX=/usr
# would ask for it): it used to move /usr/bin to the end.
got="$(PATH="/a:/usr/bin:/b" "$(command -v sh)" -c ". \"$PATHSH\" >/dev/null; PATH=/a:/usr/bin:/b; path_before /usr/bin /usr/bin; printf '%s' \"\$PATH\"")"
assert_eq "$got" "/a:/usr/bin:/b" "path_before DIR DIR leaves PATH alone"

# The default prefix, which a command over SSH relies on (HOMEBREW_PREFIX is
# unset there). Only checkable where Homebrew really is at /opt/homebrew.
if [ -x /opt/homebrew/bin/brew ]; then
  got="$(env -u HOMEBREW_PREFIX HOME="$H" PATH=/usr/bin:/bin sh -c ". \"$PATHSH\"; printf '%s' \"\$PATH\"")"
  assert_eq "$got" "$H/.local/bin:$H/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin" \
    "with HOMEBREW_PREFIX unset, /opt/homebrew is found"
else
  echo "  skip: no Homebrew at /opt/homebrew"
fi

finish
