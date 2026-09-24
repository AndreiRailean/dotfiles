#!/bin/sh
# install.sh must wire the loader into the login shell's rc even when that rc
# doesn't exist yet.
#
# macOS ships no ~/.zshrc, and zsh is its default shell. wire_shell_rc used to
# skip any rc that didn't exist, so on a brand-new Mac nothing ever sourced
# init.sh: no aliases (vim kept resolving to the system vim despite nvim being
# installed), no PATH additions, no prompt. Other shells' rc files are still
# left alone when absent — creating a ~/.bashrc nobody reads would be noise.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
INST="$REPO/install.sh"

command -v bash >/dev/null 2>&1 || { echo "  skip: bash needed"; finish; }

# Extract the real implementation rather than a paraphrase of it.
FN="$(sed -n '/^wire_shell_rc() {$/,/^}$/p' "$INST")"
[ -n "$FN" ] && pass "found wire_shell_rc in install.sh" || fail "found wire_shell_rc in install.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT INT TERM

# run_wire <login shell>: fresh HOME with no rc files, then wire both.
run_wire() {
  rm -rf "$T/home"; mkdir -p "$T/home"
  HOME="$T/home" SHELL="$1" bash -c "$FN
wire_shell_rc \"\$HOME/.bashrc\"
wire_shell_rc \"\$HOME/.zshrc\"" >/dev/null
}

run_wire /bin/zsh
if grep -qF 'shell/init.sh' "$T/home/.zshrc" 2>/dev/null; then
  pass "zsh login shell: missing ~/.zshrc is created with the loader"
else
  fail "zsh login shell: missing ~/.zshrc is created with the loader"
fi
[ ! -e "$T/home/.bashrc" ] && pass "zsh login shell: absent ~/.bashrc left alone" \
  || fail "zsh login shell: absent ~/.bashrc left alone"

run_wire /bin/bash
if grep -qF 'shell/init.sh' "$T/home/.bashrc" 2>/dev/null; then
  pass "bash login shell: missing ~/.bashrc is created with the loader"
else
  fail "bash login shell: missing ~/.bashrc is created with the loader"
fi
[ ! -e "$T/home/.zshrc" ] && pass "bash login shell: absent ~/.zshrc left alone" \
  || fail "bash login shell: absent ~/.zshrc left alone"

# Idempotent: a second run must not append a second loader.
HOME="$T/home" SHELL=/bin/bash bash -c "$FN
wire_shell_rc \"\$HOME/.bashrc\"" >/dev/null
n="$(grep -c 'shell/init.sh' "$T/home/.bashrc")"
assert_eq "$n" "1" "re-run does not duplicate the loader"

finish
