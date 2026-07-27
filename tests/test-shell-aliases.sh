#!/bin/sh
# shell package: the vim family resolves to neovim when nvim is installed
# (distros ship a preinstalled vim that otherwise wins), and leaves real vim
# alone when it isn't.
HERE="$(dirname "$0")"
. "$HERE/lib.sh"
REPO="$(cd "$HERE/.." && pwd)"
ALIASES="$REPO/shell/.config/shell/aliases.sh"

[ -f "$ALIASES" ] && pass "aliases.sh exists" || fail "aliases.sh exists"

# Sandbox PATH: only what we put in it, so `command -v nvim` is ours to control.
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT INT TERM

# Source aliases.sh with PATH=$BIN and print the alias table. PATH is narrowed
# inside the child (not as an assignment prefix — that would hide bash itself).
alias_table() { bash --norc -c "PATH='$BIN'; . '$ALIASES' 2>/dev/null; alias" 2>/dev/null; }

# ── nvim absent: no vim aliases, real vim keeps working ──
out="$(alias_table)"
assert_not_contains "$out" "alias vim=" "no vim alias without nvim"
assert_not_contains "$out" "alias vi=" "no vi alias without nvim"

# ── nvim present: vim/vi/vimdiff point at it ──
printf '#!/bin/sh\nexit 0\n' >"$BIN/nvim"
chmod +x "$BIN/nvim"
out="$(alias_table)"
assert_contains "$out" "alias vim='nvim'" "vim -> nvim"
assert_contains "$out" "alias vi='nvim'" "vi -> nvim"
assert_contains "$out" "alias vimdiff='nvim -d'" "vimdiff -> nvim -d"

# EDITOR/VISUAL cover non-interactive callers (git, etc.) where aliases don't apply
ENV_SH="$REPO/shell/.config/shell/env.sh"
grep -q '^export EDITOR="nvim"' "$ENV_SH" && pass "EDITOR=nvim" || fail "EDITOR=nvim"
grep -q '^export VISUAL="nvim"' "$ENV_SH" && pass "VISUAL=nvim" || fail "VISUAL=nvim"

# install.sh pins the system-wide vim alternative (Debian: nvim and vim.basic
# register at equal priority, so auto mode is decided by install order)
grep -q 'update-alternatives --set "\$group" "\$cand"' "$REPO/install.sh" \
  && pass "install.sh pins vim alternatives" || fail "install.sh pins vim alternatives"
grep -Eq 'for group in vim vi ' "$REPO/install.sh" \
  && pass "install.sh covers the vim/vi groups" || fail "install.sh covers the vim/vi groups"
grep -q "for group in .*\beditor\b" "$REPO/install.sh" \
  && fail "install.sh leaves the 'editor' group alone" || pass "install.sh leaves the 'editor' group alone"

# doctor.sh warns when the vim binary is still classic vim
grep -q 'classic vim, not neovim' "$REPO/doctor.sh" \
  && pass "doctor.sh reports vim/nvim mismatch" || fail "doctor.sh reports vim/nvim mismatch"

# Fragment still parses under both shells that source it
sh -n "$ALIASES" && pass "aliases.sh parses (sh)" || fail "aliases.sh parses (sh)"
bash -n "$ALIASES" && pass "aliases.sh parses (bash)" || fail "aliases.sh parses (bash)"
bash -n "$REPO/install.sh" && pass "install.sh parses" || fail "install.sh parses"
bash -n "$REPO/doctor.sh" && pass "doctor.sh parses" || fail "doctor.sh parses"

finish
