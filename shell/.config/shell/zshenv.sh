# Sourced from ~/.zshenv, so by every zsh. Only a shell that starts without
# the dotfiles PATH needs it: a command run over SSH, which reads no other rc,
# or cron. A zsh started from a dotfiles shell inherits that PATH, including a
# venv or fnm activated since, and running path.sh again would reorder it.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) [ -r "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh" ] &&
       . "${XDG_CONFIG_HOME:-$HOME/.config}/shell/path.sh" ;;
esac
