#!/bin/sh
# Without update-alternatives (macOS), install.sh points the vim names at nvim
# with symlinks in ~/.local/bin.
#
# macOS's /usr/bin/vim is classic vim and sits on the sealed system volume, so
# it can't be repointed. The vim -> nvim aliases only reach interactive shells;
# scripts, sudo and doctor.sh itself still ran classic vim.
# ~/.local/bin precedes /usr/bin on PATH (path.sh), so a link there wins for
# every process. A real file already sitting at one of those names is the
# user's own and must not be clobbered.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

FN="$(sed -n '/^link_vim_to_nvim() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found link_vim_to_nvim in install.sh" || fail "found link_vim_to_nvim in install.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM
mkdir -p "$T/home/.local/bin" "$T/bin"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/nvim"; chmod +x "$T/bin/nvim"
printf 'mine\n' >"$T/home/.local/bin/vi"      # user's own file: keep it

run() { HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" bash -c "$FN
link_vim_to_nvim" >/dev/null; }
run

vim_link="$(readlink "$T/home/.local/bin/vim" 2>/dev/null || true)"
assert_eq "$vim_link" "$T/bin/nvim" "~/.local/bin/vim links to nvim"
[ ! -L "$T/home/.local/bin/vi" ] && [ "$(cat "$T/home/.local/bin/vi")" = "mine" ] \
  && pass "a real file named vi is left alone" || fail "a real file named vi is left alone"

# Idempotent, and follows nvim if it moves (e.g. brew prefix change).
mkdir -p "$T/bin2"; mv "$T/bin/nvim" "$T/bin2/nvim"
HOME="$T/home" PATH="$T/bin2:/usr/bin:/bin" bash -c "$FN
link_vim_to_nvim" >/dev/null
assert_eq "$(readlink "$T/home/.local/bin/vim")" "$T/bin2/nvim" "re-run repoints a stale link"

finish
