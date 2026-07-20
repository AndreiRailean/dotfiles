# Starship prompt — interactive shells only.
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

if command -v starship >/dev/null 2>&1; then
  if [ -n "$ZSH_VERSION" ]; then
    eval "$(starship init zsh)"
  elif [ -n "$BASH_VERSION" ]; then
    eval "$(starship init bash)"
  fi
fi

# Terminal/tab title. Starship doesn't set it, and inside tmux the set-titles
# option handles it — so only set it from the shell when OUTSIDE tmux. Shows
# the current directory (~ for $HOME).
if [ -z "$TMUX" ]; then
  if [ -n "$BASH_VERSION" ]; then
    __set_title() { printf '\033]0;%s\007' "${PWD/#$HOME/\~}"; }
    case ":$PROMPT_COMMAND:" in
      *__set_title*) ;;                                    # already added
      *) PROMPT_COMMAND="__set_title${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
    esac
  elif [ -n "$ZSH_VERSION" ]; then
    __set_title() { print -Pn '\e]0;%~\a'; }
    autoload -Uz add-zsh-hook && add-zsh-hook precmd __set_title
  fi
fi
