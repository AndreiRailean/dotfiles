# Third-party tool initialisation. Each block is guarded so it's a no-op on
# machines where the tool isn't installed.

# Which shell are we in? Tools that emit init code need to know.
if [ -n "$ZSH_VERSION" ]; then _sh=zsh
elif [ -n "$BASH_VERSION" ]; then _sh=bash
else _sh=sh
fi

# fnm (Fast Node Manager) — the binary lives inside FNM_PATH, so add it first.
FNM_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/fnm"
if [ -d "$FNM_PATH" ]; then
  path_prepend "$FNM_PATH"
  command -v fnm >/dev/null 2>&1 && eval "$(fnm env --shell "$_sh")"
fi

# Deno
[ -r "$HOME/.deno/env" ] && . "$HOME/.deno/env"

# fzf — fuzzy finder: Ctrl-R history, Ctrl-T files, Alt-C cd. fzf 0.48+ emits
# integration via `fzf --bash|--zsh`; older packages ship scripts under
# /usr/share, so fall back to sourcing those.
if command -v fzf >/dev/null 2>&1 && { [ "$_sh" = bash ] || [ "$_sh" = zsh ]; }; then
  if fzf --"$_sh" >/dev/null 2>&1; then
    eval "$(fzf --"$_sh")"
  else
    for _f in "/usr/share/fzf/key-bindings.$_sh" "/usr/share/doc/fzf/examples/key-bindings.$_sh" \
              "/usr/share/fzf/completion.$_sh"   "/usr/share/doc/fzf/examples/completion.$_sh"; do
      [ -r "$_f" ] && . "$_f"
    done
    unset _f
  fi
  # Let fzf list files via ripgrep (fast, respects .gitignore) when available.
  if command -v rg >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
fi

# direnv — per-directory environments loaded from .envrc
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook "$_sh")"

unset _sh
