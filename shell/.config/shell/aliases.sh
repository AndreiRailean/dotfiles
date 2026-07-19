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

# cd shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# git — mirrors the aliases in ~/.config/git/config
alias g='git'
alias gs='git s'
alias gd='git d'
alias lg='git lg'
