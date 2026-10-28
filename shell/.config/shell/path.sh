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

# path_before DIR ANCHOR: make sure DIR comes before (the first) ANCHOR. If it
# doesn't, DIR moves to just before ANCHOR, not to the front, so whatever was
# put ahead of it (a venv, fnm, pyenv's shims) stays ahead. With no ANCHOR on
# PATH, DIR is added last if it's missing, and otherwise left where it is.
path_before() {
  [ -d "$1" ] && [ "$1" != "$2" ] || return 0
  _pb=":$PATH:"
  case "$_pb" in
    *":$2:"*) case "${_pb%%:"$2":*}:" in *":$1:"*) unset _pb; return 0 ;; esac ;;
    *":$1:"*) unset _pb; return 0 ;;
  esac
  while :; do
    case "$_pb" in
      *":$1:"*) _pb="${_pb%%:"$1":*}:${_pb#*:"$1":}" ;;
      *) break ;;
    esac
  done
  case "$_pb" in
    *":$2:"*) _pb="${_pb%%:"$2":*}:$1:$2:${_pb#*:"$2":}" ;;
    *)        _pb="$_pb$1:" ;;
  esac
  _pb="${_pb#:}"; _pb="${_pb%:}"
  PATH="$_pb"
  unset _pb
}

# zshenv.sh sets _path_keep_order. Every zsh reads ~/.zshenv, and one started
# from a shell that ordered its own PATH (a venv or fnm activated) must keep
# that order, so nothing moves to the front then: each dir only goes ahead of
# /usr/bin if it isn't already. A command run over SSH starts from
# /usr/bin:/bin:… and gets the same dirs, in the same order, either way.
if [ -n "${_path_keep_order:-}" ]; then
  path_before "$HOME/.local/bin" /usr/bin
  path_before "$HOME/bin" /usr/bin
fi

# Apple-silicon Homebrew. Its installer puts `brew shellenv` in ~/.zprofile,
# which only a login shell reads, and path_helper demotes it there anyway.
# Through ~/.zshenv, a command run over SSH gets brew's bash and tools rather
# than Apple's /bin/bash 3.2. Ahead of the system's dirs only: brew carries
# python, node and ruby, which mustn't jump a venv or fnm.
_hb="${HOMEBREW_PREFIX:-/opt/homebrew}"
if [ -x "$_hb/bin/brew" ]; then
  path_before "$_hb/bin" /usr/bin
  path_before "$_hb/sbin" /usr/bin
fi
unset _hb

if [ -z "${_path_keep_order:-}" ]; then
  path_prepend "$HOME/bin"
  path_prepend "$HOME/.local/bin"
fi

export PATH
