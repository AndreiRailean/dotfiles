# Aliases — harmless in non-interactive shells, so defined unconditionally.

# ls colour flag differs: GNU coreutils (Linux/WSL) vs BSD (macOS).
if ls --color=auto >/dev/null 2>&1; then
  alias ls='ls --color=auto'
else
  alias ls='ls -G'
fi

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias grep='grep --color=auto'

# bat — cat with syntax highlighting. Debian/Ubuntu ships the binary as
# `batcat`; alias `bat` to it there so `bat` works everywhere. Use cat as a
# drop-in (--paging=never keeps cat's dump-and-exit behaviour). When piped,
# bat auto-disables decorations, so `cat file | ...` still behaves like cat.
if command -v batcat >/dev/null 2>&1; then
  alias bat='batcat'
  alias cat='batcat --paging=never'
elif command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never'
fi

# cd shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# git — mirrors the aliases in ~/.config/git/config
alias g='git'
alias gs='git s'
alias gd='git d'
alias lg='git lg'
