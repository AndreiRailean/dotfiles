# PATH construction — idempotent, so nested shells (tmux, subshells) don't
# accumulate duplicate entries.

# path_prepend DIR: put DIR at the front of PATH if it exists, removing any
# copy further back. Left defined on purpose — tools.sh reuses it.
#
# Moving, not skipping, an entry that is already present is load-bearing on
# macOS: every zsh login shell runs /usr/libexec/path_helper (from
# /etc/zprofile), which rebuilds PATH with /etc/paths (/usr/bin, …) first and
# demotes everything it inherited behind them. A shell started from another
# shell (a herdr/tmux pane, a terminal tab) therefore arrives with
# ~/.local/bin already on PATH but behind /usr/bin, and a skip-if-present check
# would leave it there — so scripts got /usr/bin/vim instead of the nvim link.
path_prepend() {
  [ -d "$1" ] || return 0
  _pp=":$PATH:"
  while :; do
    case "$_pp" in
      *":$1:"*) _pp="${_pp%%:"$1":*}:${_pp#*:"$1":}" ;;
      *) break ;;
    esac
  done
  _pp="${_pp#:}"; _pp="${_pp%:}"
  PATH="$1${_pp:+:$_pp}"
  unset _pp
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"

export PATH
