# PATH construction — idempotent, so nested shells (tmux, subshells) don't
# accumulate duplicate entries.

# path_prepend DIR: add DIR to the front of PATH if it exists and isn't
# already present. Left defined on purpose — tools.sh reuses it.
path_prepend() {
  case ":$PATH:" in
    *":$1:"*) ;;                       # already present, do nothing
    *) [ -d "$1" ] && PATH="$1:$PATH" ;;
  esac
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

export PATH
