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
