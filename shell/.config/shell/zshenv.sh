# Sourced from ~/.zshenv, so by every zsh: a command run over SSH, which reads
# no other rc, gets path.sh's dirs. In keep-order mode, so a zsh started from
# another shell doesn't reorder the PATH it inherited (a venv or fnm ahead of
# brew, say). An interactive zsh runs path.sh again from ~/.zshrc, in full.
if [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh" ]; then
  _path_keep_order=1
  . "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh"
  unset _path_keep_order
fi
