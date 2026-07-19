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

unset _sh
